const express = require('express');
const admin = require('firebase-admin');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

// Initialize Firebase Admin SDK
// Service account will be added from environment variable
const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

// Health check endpoint
app.get('/', (req, res) => {
  res.json({ 
    status: 'running',
    message: 'Smart Classroom Notification Server' 
  });
});

// Send notification endpoint
app.post('/send-notification', async (req, res) => {
  try {
    const { fcmToken, title, body, data } = req.body;

    // Validate input
    if (!fcmToken || !title || !body) {
      return res.status(400).json({ 
        success: false, 
        error: 'Missing required fields: fcmToken, title, body' 
      });
    }

    console.log('Sending notification to:', fcmToken);

    // Send notification using Admin SDK
    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: data || {},
      token: fcmToken,
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
