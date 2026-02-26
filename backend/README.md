# Smart Classroom Notification Server

Backend server for sending FCM push notifications to admin devices.

## Features
- Express.js REST API
- Firebase Admin SDK for FCM
- CORS enabled
- Free hosting on Render.com

## Deployment Steps

### 1. Get Firebase Service Account JSON

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **smartclassroommontoring**
3. Click ⚙️ (Settings) → **Project settings**
4. Go to **Service accounts** tab
5. Click **Generate new private key**
6. Download the JSON file

### 2. Deploy to Render.com

1. Create account at [render.com](https://render.com/) (free)
2. Click **New +** → **Web Service**
3. Connect your GitHub/GitLab (or deploy from local)
4. Select this `backend` folder
5. Configure:
   - **Name**: smart-classroom-notifications
   - **Environment**: Node
   - **Build Command**: `npm install`
   - **Start Command**: `npm start`
   - **Plan**: Free

### 3. Add Environment Variable

In Render.com dashboard:
1. Go to **Environment** tab
2. Add variable:
   - **Key**: `FIREBASE_SERVICE_ACCOUNT`
   - **Value**: Paste entire service account JSON content
3. Save

### 4. Get Your Backend URL

After deployment, Render will give you a URL like:
```
https://smart-classroom-notifications.onrender.com
```

Copy this URL and update it in your Flutter app.

## API Endpoints

### POST /send-notification

Send push notification to admin device.

**Request Body:**
```json
{
  "fcmToken": "admin_device_token",
  "title": "Violation Detected",
  "body": "Student: John - Period 2 - Duration: 15 min",
  "data": {
    "studentName": "John",
    "period": "2"
  }
}
```

**Response:**
```json
{
  "success": true,
  "messageId": "projects/.../messages/...",
  "message": "Notification sent successfully"
}
```

## Testing Locally (Optional)

```bash
npm install
export FIREBASE_SERVICE_ACCOUNT='<paste-json-here>'
npm start
```

Server will run at http://localhost:3000
