# 🚀 Complete Deployment Guide - Smart Classroom Notifications

Follow these steps to deploy your backend and enable notifications from student to admin device.

---

## ✅ Step 1: Get Firebase Service Account Key

1. Open [Firebase Console](https://console.firebase.google.com/)
2. Click on your project: **smartclassroommontoring**
3. Click ⚙️ **Settings** → **Project settings**
4. Go to **Service accounts** tab
5. Click **Generate new private key** button
6. Click **Generate key** (downloads JSON file)
7. **Keep this file safe!** You'll need it in Step 3

---

## ✅ Step 2: Create Render.com Account (FREE)

1. Go to [render.com](https://render.com/)
2. Click **Get Started** or **Sign Up**
3. Sign up with GitHub/GitLab/Email (your choice)
4. Verify your email
5. Login to Render dashboard

**Cost: ₹0 (100% Free, no credit card needed)**

---

## ✅ Step 3: Deploy Backend to Render.com

### Option A: Deploy from Local Folder (Easiest)

1. In Render dashboard, click **New +** → **Web Service**
2. Select **Build and deploy from a Git repository** → **Next**
3. Click **Public Git repository**
4. Paste this URL (if you pushed to GitHub):
   ```
   https://github.com/YOUR_USERNAME/SmartClassroom_montoring
   ```
   OR Click **Upload from computer** and select the `backend` folder

5. Configure the service:
   - **Name**: `smart-classroom-notifications`
   - **Region**: Singapore (closest to India)
   - **Branch**: main
   - **Root Directory**: `backend`
   - **Environment**: Node
   - **Build Command**: `npm install`
   - **Start Command**: `npm start`
   - **Plan**: Free

6. Click **Create Web Service**

### Step 3.1: Add Firebase Service Account

1. While deployment is running, go to **Environment** tab (left sidebar)
2. Click **Add Environment Variable**
3. Add:
   - **Key**: `FIREBASE_SERVICE_ACCOUNT`
   - **Value**: Open the JSON file you downloaded in Step 1, **copy entire content** and paste here
   
   Example:
   ```json
   {"type":"service_account","project_id":"smartclassroommontoring","private_key_id":"abc123...","private_key":"-----BEGIN PRIVATE KEY-----\n...","client_email":"firebase-adminsdk-..."}
   ```

4. Click **Save Changes**
5. Render will automatically redeploy with the new environment variable

### Step 3.2: Wait for Deployment

- Deployment takes **3-5 minutes**
- You'll see logs in the dashboard
- Wait for: ✅ **"Your service is live"**

### Step 3.3: Copy Your Backend URL

After deployment succeeds, you'll see your URL at the top:
```
https://smart-classroom-notifications.onrender.com
```

**Copy this URL!** You need it for Step 4.

---

## ✅ Step 4: Update Flutter App with Backend URL

1. Open: `lib/services/monitor_service.dart`
2. Find this line (around line 123):
   ```dart
   const backendUrl = 'YOUR_RENDER_URL_HERE/send-notification';
   ```

3. Replace with your actual Render URL:
   ```dart
   const backendUrl = 'https://smart-classroom-notifications.onrender.com/send-notification';
   ```

4. Save the file

---

## ✅ Step 5: Build and Install APK

### Build APK:
```bash
flutter build apk --release
```

### Install on Both Devices:

**Admin Device (V2312):**
```bash
adb connect 192.168.0.106:5555
adb -s 192.168.0.106:5555 install build/app/outputs/flutter-apk/app-release.apk
```

**Student Device:**
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

---

## ✅ Step 6: Test Notifications

### 6.1: Admin Login
1. Open app on admin device (V2312)
2. Login as admin
3. FCM token will be saved automatically
4. Keep admin app open (or running in background)

### 6.2: Trigger Violation from Student Device
1. Open app on student device
2. Login as student
3. Start monitoring
4. Trigger violation (leave app)

### 6.3: Check Admin Device
**Admin mobile ku notification varum!** 🔔

You should see:
```
🔔 Violation Detected!
Praveen - Period 2 - 15 min
```

---

## 🔍 Troubleshooting

### ❌ Admin not receiving notifications?

1. **Check Backend Logs:**
   - Go to Render dashboard → Your service → **Logs** tab
   - Look for: "Sending notification to:" and "Notification sent successfully"

2. **Check Flutter Logs:**
   ```bash
   adb logcat | findstr "FCM"
   ```
   - Should see: `[FCM] ✅ Push notification sent successfully!`

3. **Test Backend Directly:**
   - Open [Postman](https://www.postman.com/) or browser
   - Send POST request:
     ```
     POST https://smart-classroom-notifications.onrender.com/send-notification
     
     Body (JSON):
     {
       "fcmToken": "YOUR_ADMIN_FCM_TOKEN",
       "title": "Test",
       "body": "Testing notification"
     }
     ```
   - Should return: `{"success": true}`

4. **Check Admin Token:**
   - Make sure admin logged in and token saved
   - Check Firestore: `admins/{uid}/fcmToken` should have value

5. **Backend Sleeping?**
   - Free Render services sleep after 15 minutes of inactivity
   - First request may take 30-60 seconds to "wake up"
   - Subsequent requests are instant

---

## 📊 Cost Breakdown

| Service | Cost | Limits |
|---------|------|--------|
| Render.com Web Service | **₹0** | 750 hours/month (enough for 24/7) |
| Firebase Firestore | **₹0** | 50K reads/day, 20K writes/day |
| Firebase Cloud Messaging | **₹0** | Unlimited notifications |
| **TOTAL** | **₹0** | **FREE FOREVER** |

---

## 🎉 Success Criteria

After completing all steps:

✅ Student app detects violation  
✅ Violation saved to Firestore  
✅ Student app calls backend server  
✅ Backend sends notification via Admin SDK  
✅ **Admin mobile ku notification varum!** 🔔

---

## 📝 Important Notes

1. **First Request After Sleep:**
   - Render free tier sleeps after 15 min inactivity
   - First notification may take 30-60 seconds
   - Solution: Use [UptimeRobot](https://uptimerobot.com/) to ping your backend every 5 minutes (keeps it awake)

2. **Backend URL:**
   - Never expires
   - No maintenance needed
   - Works 24/7

3. **Security:**
   - Service account JSON is safe (stored as environment variable)
   - Not exposed in APK
   - Only your backend can access it

4. **Firestore Rules:**
   - Make sure your rules allow reading from `admins` collection
   - Current rules should work fine

---

## 🆘 Need Help?

If notifications still don't work after following all steps:

1. Share Render logs (from dashboard)
2. Share Flutter logs (`adb logcat | findstr "FCM"`)
3. Share Firestore screenshot (admins collection)

---

**Ready to deploy? Start with Step 1!** 🚀
