const express = require('express');
const admin = require('firebase-admin');
const cors = require('cors');

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

// Start server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`✅ Smart Classroom Notification Server running on port ${PORT}`);
});
