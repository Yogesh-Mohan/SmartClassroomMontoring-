const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');

admin.initializeApp();

function sanitizeDocKey(value) {
  return String(value || '')
    .trim()
    .replace(/[^a-zA-Z0-9_-]/g, '_')
    .slice(0, 120);
}

function istDateKey(date = new Date()) {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Kolkata',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  return formatter.format(date);
}

async function upsertRuleSummaryAlert(violation) {
  const studentUID = (violation?.studentUID || '').toString().trim();
  const regNo = (violation?.regNo || '').toString().trim();
  const ownerKey = (regNo || studentUID || '').toString().trim();
  const period = (violation?.period || 'Unknown').toString().trim();
  const studentName = (violation?.name || 'Student').toString().trim();

  const recipientKeys = [studentUID, regNo].filter(Boolean);
  if (recipientKeys.length === 0) return;

  const primaryKey = sanitizeDocKey(recipientKeys[0]);
  if (!primaryKey) return;

  const dayKey = istDateKey();
  const docId = `rule_${primaryKey}_${dayKey}`;
  const alertRef = admin.firestore().collection('student_alerts').doc(docId);

  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(alertRef);
    const currentCount = snap.exists
      ? Number(snap.data()?.violationCount || 0)
      : 0;
    const nextCount = currentCount + 1;

    const payload = {
      type: 'rule_summary',
      title: 'Rule Broken Alert',
      message: `${nextCount} rule break${nextCount > 1 ? 's' : ''} detected today. Please follow classroom rules.`,
      recipientKeys,
      ownerKey,
      isRead: false,
      summaryDate: dayKey,
      violationCount: nextCount,
      periods: admin.firestore.FieldValue.arrayUnion(period),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      studentName,
    };

    if (!snap.exists) {
      payload.createdAt = admin.firestore.FieldValue.serverTimestamp();
    }

    tx.set(alertRef, payload, { merge: true });
  });
}

async function clearCollectionInBatches(collectionName, batchSize = 400) {
  const db = admin.firestore();
  while (true) {
    const snapshot = await db.collection(collectionName).limit(batchSize).get();
    if (snapshot.empty) break;

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
}

async function clearAllTaskSubmissions(batchSize = 300) {
  const db = admin.firestore();
  const tasksSnapshot = await db.collection('tasks').get();

  for (const taskDoc of tasksSnapshot.docs) {
    while (true) {
      const submissions = await taskDoc.ref
        .collection('submissions')
        .limit(batchSize)
        .get();
      if (submissions.empty) break;

      const batch = db.batch();
      submissions.docs.forEach((submissionDoc) => batch.delete(submissionDoc.ref));
      await batch.commit();
    }
  }
}

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

      await upsertRuleSummaryAlert(violation);
      return { successCount, failureCount };
      
    } catch (error) {
      console.error('❌ Error sending notification:', error);
      return null;
    }
  });

exports.resetStudentTaskCycle = functions.pubsub
  .schedule('0 0 */3 * *')
  .timeZone('Asia/Kolkata')
  .onRun(async () => {
    const now = new Date();
    const nextResetAt = new Date(now.getTime() + 3 * 24 * 60 * 60 * 1000);
    const cycleKey = istDateKey(now);

    await clearAllTaskSubmissions();
    await clearCollectionInBatches('student_alerts');

    await admin
      .firestore()
      .collection('system')
      .doc('taskReset')
      .set(
        {
          cycleKey,
          lastResetAt: admin.firestore.FieldValue.serverTimestamp(),
          nextResetAt: admin.firestore.Timestamp.fromDate(nextResetAt),
        },
        { merge: true }
      );

    console.log(`✅ 3-day reset completed for cycle ${cycleKey}`);
    return null;
  });
