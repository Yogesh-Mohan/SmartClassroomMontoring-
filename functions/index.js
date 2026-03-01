const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');

admin.initializeApp();

async function sendNotificationToToken({ token, title, body, data = {} }) {
  const message = {
    token,
    notification: { title, body },
    data: Object.fromEntries(
      Object.entries(data).map(([key, value]) => [key, String(value)])
    ),
    android: {
      priority: 'high',
      notification: {
        sound: 'default',
        channelId: 'smart_classroom_notifications',
      },
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
          contentAvailable: true,
        },
      },
    },
  };

  return admin.messaging().send(message);
}

async function sendNotificationToAdmins({ title, body, data = {} }) {
  const adminsSnapshot = await admin.firestore().collection('admins').get();

  if (adminsSnapshot.empty) {
    return { successCount: 0, failureCount: 0, tokenCount: 0 };
  }

  const tokens = [];
  adminsSnapshot.forEach((doc) => {
    const fcmToken = (doc.data()?.fcmToken || '').toString().trim();
    if (fcmToken) {
      tokens.push(fcmToken);
    }
  });

  if (tokens.length === 0) {
    return { successCount: 0, failureCount: 0, tokenCount: 0 };
  }

  let successCount = 0;
  let failureCount = 0;

  for (const token of tokens) {
    try {
      await sendNotificationToToken({ token, title, body, data });
      successCount++;
    } catch (sendError) {
      failureCount++;
      console.error('❌ Admin token send failed:', sendError?.message || sendError);
    }
  }

  return { successCount, failureCount, tokenCount: tokens.length };
}

exports.sendNotification = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    return res.status(405).json({ success: false, error: 'Method not allowed' });
  }

  try {
    const { fcmToken, title, body, data } = req.body || {};

    if (!fcmToken || !title || !body) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: fcmToken, title, body',
      });
    }

    const messageId = await sendNotificationToToken({
      token: String(fcmToken).trim(),
      title: String(title),
      body: String(body),
      data: data && typeof data === 'object' ? data : {},
    });

    return res.status(200).json({ success: true, messageId });
  } catch (error) {
    console.error('sendNotification HTTPS function error:', error);
    return res.status(500).json({
      success: false,
      error: error?.message || 'Unknown error',
    });
  }
});

exports.notifyAdmins = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    return res.status(405).json({ success: false, error: 'Method not allowed' });
  }

  try {
    const { title, body, data } = req.body || {};

    if (!title || !body) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: title, body',
      });
    }

    const result = await sendNotificationToAdmins({
      title: String(title),
      body: String(body),
      data: data && typeof data === 'object' ? data : {},
    });

    return res.status(200).json({ success: true, ...result });
  } catch (error) {
    console.error('notifyAdmins HTTPS function error:', error);
    return res.status(500).json({
      success: false,
      error: error?.message || 'Unknown error',
    });
  }
});

/**
 * Cloud Function: Send FCM notification when a new violation is created
 * Triggers automatically when a document is added to 'violations' collection
 */
exports.sendViolationNotification = functions.firestore
  .document('violations/{violationId}')
  .onCreate(async (snap, context) => {
    try {
      const violation = snap.data();
      
      console.log('🔔 New violation detected:', violation);
      
      // Get violation details
      const studentName = violation.name || 'Unknown';
      const period = violation.period || 'Unknown';
      const secondsUsed = violation.secondsUsed || 0;
      
      const { successCount, failureCount, tokenCount } = await sendNotificationToAdmins({
        title: '🔔 Violation Detected!',
        body: `${studentName} - ${period} - ${secondsUsed}s phone usage`,
        data: {
          studentName,
          period,
          secondsUsed: secondsUsed.toString(),
          timestamp: new Date().toISOString(),
          type: 'violation',
        },
      });

      if (tokenCount === 0) {
        console.log('⚠️ No admin tokens found');
        return null;
      }

      console.log(`📊 Success: ${successCount}, Failure: ${failureCount}`);
      return { successCount, failureCount };
      
    } catch (error) {
      console.error('❌ Error sending notification:', error);
      return null;
    }
  });
