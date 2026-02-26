# 🔑 FCM Server Key Setup

## ⚠️ Required: Get Your FCM Server Key

**Step 1: Open Firebase Console**
```
https://console.firebase.google.com
```

**Step 2: Select Your Project**
```
Project: smartclassroommontoring
```

**Step 3: Navigate to Cloud Messaging Settings**
```
1. Click ⚙️ Settings icon (top left)
2. Select "Project settings"
3. Go to "Cloud Messaging" tab
4. Scroll down to "Cloud Messaging API (Legacy)"
5. Find "Server key"
```

**Step 4: Copy Server Key**
```
It looks like:
AAAAxxxxxxx:APAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**Step 5: Add to Code**

Open: `lib/services/monitor_service.dart`

Find line ~124:
```dart
const fcmServerKey = 'YOUR_FCM_SERVER_KEY_HERE';
```

Replace with YOUR actual key:
```dart
const fcmServerKey = 'AAAAxxxxxxx:APAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
```

---

## 🛡️ Security Warning

**This method embeds the server key in the app** — anyone can decompile the APK and see it.

**For production apps**, use Firebase Cloud Functions to send notifications securely:
```
Student App → Cloud Function → FCM
```

**For academic/demo projects** → current implementation is acceptable.

---

## ✅ After Adding Server Key

1. Save the file
2. Rebuild APK:
   ```powershell
   flutter build apk --release
   ```
3. Install on both devices
4. Test violation → Admin receives notification 🔔
