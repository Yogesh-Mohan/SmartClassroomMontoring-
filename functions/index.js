const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

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
      
      // Fetch all admin FCM tokens from Firestore
      const adminsSnapshot = await admin.firestore()
        .collection('admins')
        .get();
      
      if (adminsSnapshot.empty) {
        console.log('⚠️ No admin documents found');
        return null;
      }
      
      // Collect all valid FCM tokens
      const tokens = [];
      adminsSnapshot.forEach((doc) => {
        const fcmToken = doc.data().fcmToken;
        if (fcmToken && fcmToken.trim() !== '') {
          tokens.push(fcmToken);
          console.log(`✅ Found admin token: ${fcmToken.substring(0, 20)}...`);
        }
      });
      
      if (tokens.length === 0) {
        console.log('⚠️ No admin tokens found');
        return null;
      }
      
      // Create notification payload
      const payload = {
        notification: {
          title: '🔔 Violation Detected!',
          body: `${studentName} - ${period} - ${secondsUsed}s phone usage`,
        },
        data: {
          studentName: studentName,
          period: period,
          secondsUsed: secondsUsed.toString(),
          timestamp: new Date().toISOString(),
        },
      };
      
      // Send to all admin devices
      const response = await admin.messaging().sendToDevice(tokens, payload, {
        priority: 'high',
        timeToLive: 60 * 60 * 24, // 24 hours
      });
      
      console.log('✅ Notification sent successfully:', response);
      console.log(`📊 Success: ${response.successCount}, Failure: ${response.failureCount}`);
      
      return response;
      
    } catch (error) {
      console.error('❌ Error sending notification:', error);
      return null;
    }
  });
