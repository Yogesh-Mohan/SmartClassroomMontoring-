# Quick Setup Guide - Sync Existing Admin Users

## What This Does
Synchronizes existing admin/advisor user roles from Firestore to Firebase Auth custom claims. This is a one-time setup.

## Prerequisites
```bash
npm install -g firebase-tools
firebase login
```

## Quick Start (3 steps)

### Step 1: Get Your Function URL
```bash
cd functions
npm run logs
# Or check Firebase Console → Functions → syncUserRoleToClaims
```

Look for a URL like: `https://us-central1-smartclassroommontoring.cloudfunctions.net/syncUserRoleToClaims`

### Step 2: Find All Admin/Advisor UIDs
```bash
# Option A: From Firebase Console
# Go to Firestore → users collection
# Filter where "isAdmin" == true OR "role" == "admin"
# Copy the document IDs (UIDs)

# Option B: Using Firebase Admin SDK
node -e "
const admin = require('firebase-admin');
admin.initializeApp();
admin.firestore()
  .collection('users')
  .where('isAdmin', '==', true)
  .get()
  .then(snap => {
    snap.forEach(doc => console.log(doc.id));
    process.exit(0);
  });
"
```

### Step 3: Sync Each UID
```bash
#!/bin/bash
FUNCTION_URL="https://us-central1-smartclassroommontoring.cloudfunctions.net/syncUserRoleToClaims"

# List of admin UIDs (get these from step 2)
ADMIN_UIDS=(
  "uid1"
  "uid2"
  "uid3"
)

for uid in "${ADMIN_UIDS[@]}"; do
  echo "Syncing $uid..."
  curl -X POST "$FUNCTION_URL" \
    -H "Content-Type: application/json" \
    -d "{\"uid\": \"$uid\"}"
  echo ""
done

echo "✅ All done!"
```

## Verify It Worked
```bash
node -e "
const admin = require('firebase-admin');
admin.initializeApp();
admin.auth().getUser('uid-here').then(user => {
  console.log('Custom Claims:', user.customClaims);
}).catch(e => console.error(e));
"
```

Expected output:
```
Custom Claims: {
  isAdmin: true,
  role: 'admin',
  isAdvisor: false,
  userType: 'admin'
}
```

## For Future Admin Creations

When you create a new admin/advisor user from your app, the `onUserRoleUpdate` trigger will **automatically** sync their role to custom claims.

No manual action needed! ✨

## Troubleshooting

**Q: Function returns 404?**
A: Ensure the user/admin document exists in Firestore

**Q: Custom claims still not appearing?**
A: User needs to refresh their token:
```dart
await FirebaseAuth.instance.currentUser?.getIdToken(forceRefresh: true);
```

**Q: "Missing uid parameter"?**
A: Make sure you're sending JSON with `uid` field in POST body

---

**Questions?** Check `QUOTA_FIX_DOCUMENTATION.md` for detailed explanation.
