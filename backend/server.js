const express = require('express');
const admin = require('firebase-admin');
const cors = require('cors');
const cron = require('node-cron');
require('dotenv').config();

const app = express();


app.use(cors());
app.use(express.json());

let firebaseReady = false;

try {
  const serviceAccountRaw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!serviceAccountRaw) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT environment variable is missing');
  }

  const serviceAccount = JSON.parse(serviceAccountRaw);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
  firebaseReady = true;
} catch (error) {
  console.error('❌ Firebase Admin initialization failed:', error.message);
}

// Health check endpoint
app.get('/', (req, res) => {
  res.json({ 
    status: 'running',
    message: 'Smart Classroom Notification Server',
    firebaseReady
  });
});

// Send notification endpoint
app.post('/send-notification', async (req, res) => {
  try {
    if (!firebaseReady) {
      return res.status(503).json({
        success: false,
        error: 'Firebase Admin SDK is not configured on this server'
      });
    }

    const { fcmToken, title, body, data } = req.body;
    const token = (fcmToken || '').toString().trim();

    // Validate input
    if (!token || !title || !body) {
      return res.status(400).json({ 
        success: false, 
        error: 'Missing required fields: fcmToken, title, body' 
      });
    }

    const maskedToken = `${token.substring(0, 10)}...${token.substring(Math.max(0, token.length - 6))}`;
    console.log('Sending notification to token:', maskedToken);

    const safeData = data && typeof data === 'object'
      ? Object.fromEntries(Object.entries(data).map(([key, value]) => [key, String(value)]))
      : {};

    // Send notification using Admin SDK
    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: safeData,
      token,
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'smart_classroom_notifications'
        }
      }
    };

    const response = await admin.messaging().send(message);
    
    console.log('Notification sent successfully:', response);
    
    res.json({ 
      success: true, 
      messageId: response,
      message: 'Notification sent successfully' 
    });

  } catch (error) {
    console.error('Error sending notification:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// Send one notification payload to all admin devices
app.post('/notify-admins', async (req, res) => {
  try {
    if (!firebaseReady) {
      return res.status(503).json({
        success: false,
        error: 'Firebase Admin SDK is not configured on this server'
      });
    }

    const { title, body, data } = req.body || {};
    if (!title || !body) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: title, body'
      });
    }

    const safeData = data && typeof data === 'object'
      ? Object.fromEntries(Object.entries(data).map(([key, value]) => [key, String(value)]))
      : {};

    const db = admin.firestore();
    const tokenSet = new Set();

    const adminsSnap = await db.collection('admins').get();
    adminsSnap.forEach((doc) => {
      const token = (doc.data()?.fcmToken || '').toString().trim();
      if (token) tokenSet.add(token);
    });

    const adminTokensSnap = await db
      .collection('fcmTokens')
      .where('role', '==', 'admin')
      .get();
    adminTokensSnap.forEach((doc) => {
      const token = (doc.data()?.token || '').toString().trim();
      if (token) tokenSet.add(token);
    });

    const admin1TokenDoc = await db.collection('fcmTokens').doc('admin1').get();
    const admin1Token = (admin1TokenDoc.data()?.token || '').toString().trim();
    if (admin1Token) {
      tokenSet.add(admin1Token);
    }

    const tokens = Array.from(tokenSet);
    if (tokens.length === 0) {
      return res.status(200).json({ success: true, tokenCount: 0, successCount: 0, failureCount: 0 });
    }

    let successCount = 0;
    let failureCount = 0;

    for (const token of tokens) {
      try {
        await admin.messaging().send({
          token,
          notification: {
            title: String(title),
            body: String(body),
          },
          data: safeData,
          android: {
            priority: 'high',
            notification: {
              sound: 'default',
              channelId: 'smart_classroom_notifications'
            }
          }
        });
        successCount++;
      } catch (sendError) {
        failureCount++;
        console.error('notify-admins send failed:', sendError?.message || sendError);
      }
    }

    return res.json({
      success: true,
      tokenCount: tokens.length,
      successCount,
      failureCount
    });
  } catch (error) {
    console.error('Error in notify-admins:', error);
    return res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// ── Notify all present students (broadcast from admin monitoring screen) ──────
// Reads live_monitoring to find all non-offline students, fetches their FCM
// tokens from fcmTokens/{uid} and broadcasts the admin's message.
app.post('/notify-class', async (req, res) => {
  try {
    if (!firebaseReady) {
      return res.status(503).json({
        success: false,
        error: 'Firebase Admin SDK is not configured on this server'
      });
    }

    const { title, body } = req.body || {};
    if (!title || !body) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: title, body'
      });
    }

    const db = admin.firestore();

    // Find all students currently present (status != 'offline') in live_monitoring
    const liveSnap = await db.collection('live_monitoring').get();
    const presentUids = [];
    liveSnap.forEach((doc) => {
      const status = (doc.data()?.status || 'offline').toString();
      if (status !== 'offline') {
        presentUids.push(doc.id); // docId = studentUID
      }
    });

    if (presentUids.length === 0) {
      return res.json({
        success: true,
        message: 'No present students found',
        tokenCount: 0,
        successCount: 0,
        failureCount: 0
      });
    }

    // Fetch FCM tokens for each present student
    const tokens = [];
    for (const uid of presentUids) {
      try {
        const tokenDoc = await db.collection('fcmTokens').doc(uid).get();
        const token = (tokenDoc.data()?.token || '').toString().trim();
        if (token) tokens.push({ uid, token });
      } catch (_) {}
    }

    if (tokens.length === 0) {
      return res.json({
        success: true,
        message: 'No FCM tokens found for present students',
        tokenCount: 0,
        successCount: 0,
        failureCount: 0
      });
    }

    // Send notification to each student
    let successCount = 0;
    let failureCount = 0;

    for (const { uid, token } of tokens) {
      try {
        await admin.messaging().send({
          token,
          notification: {
            title: String(title),
            body: String(body),
          },
          data: { type: 'class_notification' },
          android: {
            priority: 'high',
            notification: {
              sound: 'default',
              channelId: 'smart_classroom_notifications'
            }
          }
        });
        successCount++;
        console.log(`✅ Class notify sent to student ${uid}`);
      } catch (sendError) {
        failureCount++;
        console.error(`❌ Class notify failed for ${uid}:`, sendError?.message || sendError);
      }
    }

    console.log(`📢 Class notification sent: ${successCount} success, ${failureCount} failed`);
    return res.json({
      success: true,
      studentCount: presentUids.length,
      tokenCount: tokens.length,
      successCount,
      failureCount
    });

  } catch (error) {
    console.error('Error in notify-class:', error);
    return res.status(500).json({ success: false, error: error.message });
  }
});

// ── Violations cleanup helper ────────────────────────────────────────────────
async function deleteOldViolations() {
  if (!firebaseReady) {
    console.warn('⚠️ Firebase not ready — skipping violations cleanup');
    return { deleted: 0, error: 'Firebase not ready' };
  }

  const db = admin.firestore();
  const cutoff = new Date(Date.now() - 2 * 24 * 60 * 60 * 1000);
  const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);
  const batchSize = 400;
  let totalDeleted = 0;

  try {
    while (true) {
      const snap = await db
        .collection('violations')
        .where('timestamp', '<', cutoffTs)
        .orderBy('timestamp')
        .limit(batchSize)
        .get();

      if (snap.empty) break;

      const batch = db.batch();
      snap.docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
      totalDeleted += snap.size;
    }

    console.log(`✅ Violations cleanup: deleted ${totalDeleted} docs older than 2 days`);
    return { deleted: totalDeleted };
  } catch (err) {
    console.error('❌ Violations cleanup error:', err.message || err);
    return { deleted: totalDeleted, error: err.message };
  }
}

// Manual trigger endpoint (for testing or on-demand cleanup)
app.post('/cleanup-violations', async (req, res) => {
  const secret = (req.headers['x-cleanup-secret'] || '').trim();
  const expected = (process.env.CLEANUP_SECRET || '').trim();
  if (expected && secret !== expected) {
    return res.status(401).json({ success: false, error: 'Unauthorized' });
  }

  const result = await deleteOldViolations();
  const success = !result.error;
  return res.status(success ? 200 : 500).json({ success, ...result });
});

// Daily cron job — runs at 00:30 AM IST every day
cron.schedule(
  '30 0 * * *',
  () => {
    console.log('🕐 Running scheduled violations cleanup...');
    deleteOldViolations();
  },
  { timezone: 'Asia/Kolkata' }
);

// Start server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`✅ Smart Classroom Notification Server running on port ${PORT}`);
});
