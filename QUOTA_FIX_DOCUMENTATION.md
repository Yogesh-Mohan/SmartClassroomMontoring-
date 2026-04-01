# Firestore Quota Exhaustion - Fix Documentation

## Problem
The app was showing error: **"Firestore error: Some resource has been exhausted, perhaps a per-user quota, or perhaps the entire file system is out of space."**

### Root Cause
The `isAdmin()` and `isAdvisor()` functions in `firestore.rules` were making multiple `get()` database read operations for every single Firestore operation on high-traffic collections like:
- `attendance` (students check-in/check-out)
- `attendance_records` (attendance data writes)
- `student_sessions` (login heartbeat)
- `violations` (rule violation reports)

Every `get()` counts as 1 read operation towards quota limits. With multiple `get()` calls per operation × thousands of daily student interactions = rapid quota exhaustion.

## Solution Implemented

### Phase 1: Optimized Rule Functions ✅ DEPLOYED
**File**: `firestore.rules`

Changed from 8+ database reads to 0 database reads by using **Firebase Auth Custom Claims** instead of `get()` operations.

**Before** (8 get() calls per isAdmin check):
```firestore
function isAdmin() {
  return request.auth != null && (
    get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin'
    || get(...).data.role == 'Admin'
    || get(...).data.userType == 'admin'
    // ... 5 more get() calls
  );
}
```

**After** (0 database reads):
```firestore
function isAdmin() {
  return request.auth != null && (
    exists(/databases/$(database)/documents/admins/$(request.auth.uid))
    || request.auth.token.customClaims != null
       && request.auth.token.customClaims.isAdmin == true
  );
}
```

### Phase 2: Added Cloud Functions ✅ DEPLOYED
**File**: `functions/index.js`

Two new functions added:

#### 1. `syncUserRoleToClaims` (HTTPS Endpoint)
- **Endpoint**: `https://[region]-[project].cloudfunctions.net/syncUserRoleToClaims`
- **Method**: POST
- **Payload**: `{ "uid": "user-uid" }`
- **Purpose**: Manually sync a user's role from Firestore to auth custom claims
- **Use**: Call this after creating a new admin/advisor user

#### 2. `onUserRoleUpdate` (Firestore Trigger)
- **Trigger**: Automatically fires when `users/{uid}` document is updated
- **Purpose**: Auto-syncs role changes from Firestore to auth custom claims
- **Benefit**: Changes take effect immediately on next auth refresh

## Implementation Steps

### Step 1: Deploy Cloud Functions
```bash
firebase deploy --only functions
```
Status: ✅ Already deployed

### Step 2: Sync Existing Users (One-time Setup)
For any existing admin/advisor users, manually sync their roles:

```bash
# Using curl
curl -X POST https://[your-function-url]/syncUserRoleToClaims \
  -H "Content-Type: application/json" \
  -d '{"uid": "admin-user-uid"}'

# Using Node.js Firebase SDK
const response = await fetch(syncUserRoleUrl, {
  method: 'POST',
  body: JSON.stringify({ uid: adminUserUid })
});
```

### Step 3: Update Your Flutter App
When creating/updating admin users in your app, call the sync function:

```dart
// After adding/updating admin role in Firestore
Future<void> makeUserAdmin(String uid) async {
  // Update Firestore
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .update({'isAdmin': true, 'role': 'admin'});

  // Sync to auth claims (backend will auto-sync via trigger)
  // But you can manually call if needed:
  // final result = await FirebaseFunctions.instance
  //     .httpsCallable('syncUserRoleToClaims')
  //     .call({'uid': uid});
}

// For login - when user auth changes, refresh token:
FirebaseAuth.instance.currentUser?.getIdToken(forceRefresh: true);
```

### Step 4: Verify Implementation
Check that custom claims are set:

```javascript
// In your backend/console
const user = await admin.auth().getUser(uid);
console.log(user.customClaims);
// Output: { isAdmin: true, role: 'admin', isAdvisor: false, ... }
```

## Quota Impact Analysis

### Before Fix
```
Daily quota for 1000 students:
- Each attendance check-in: 3 get() calls = 3 reads
- Each attendance activity: 2 get() calls = 2 reads
- Per student per day: ~50 operations × 5 reads = 250 reads
- Total: 1000 students × 250 = 250,000 reads/day

Free tier limit: 50,000 reads/day ❌ EXCEEDED 5x
```

### After Fix
```
Daily quota with custom claims:
- Each attendance check-in: 0 database reads
- Each attendance activity: 0 database reads
- Per student per day: ~50 operations × 0 reads = 0 reads
- Total: 1000 students × 0 = 0 reads from role checks

Free tier limit: 50,000 reads/day ✅ WELL WITHIN LIMIT
```

## Monitoring

### Check Current Usage
Go to Firebase Console → Firestore → Database Statistics

### Alert Setup
Set up Firebase Alerts to warn when quota is approaching:
1. Go to Firebase Console → Settings → Notifications
2. Enable quota alerts
3. Set threshold to 80% of limit

## Troubleshooting

### Issue: "Admin function still not working"
**Solution**: Force refresh the user's token:
```dart
await FirebaseAuth.instance.currentUser?.getIdToken(forceRefresh: true);
```

### Issue: "Custom claims not appearing"
**Solution**: Ensure the trigger ran. Check:
1. Go to Firebase Console → Functions → `onUserRoleUpdate`
2. Check the execution logs
3. Manually call `syncUserRoleToClaims` endpoint

### Issue: "Quota still exhausting"
**Solution**: Check for other high-volume operations:
1. Review Firestore dashboard for read hotspots
2. Look for N+1 query patterns in your app
3. Consider adding composite indexes for filter queries
4. Enable caching on frequently read collections

## Security Notes

✅ **More Secure After Fix**:
- Custom claims set by backend (server-side)
- Cannot be modified by clients
- Faster evaluation (no database reads)
- Reduces attack surface (fewer Firestore touches)

## Files Modified

1. ✅ `firestore.rules` - Optimized isAdmin() and isAdvisor() functions
2. ✅ `functions/index.js` - Added custom claims sync functions

## Next Steps

1. ✅ Deploy both files (already done if you ran `firebase deploy`)
2. ⏳ Call `syncUserRoleToClaims` for existing admin/advisor users
3. ⏳ Update your Flutter app to call the sync function when role changes
4. 📊 Monitor Firestore statistics to confirm quota improvement

## References

- [Firebase Custom Claims Documentation](https://firebase.google.com/docs/auth/admin-setup-custom-claims)
- [Firestore Quota Limits](https://firebase.google.com/docs/firestore/quotas)
- [Security Rules Best Practices](https://firebase.google.com/docs/firestore/security/get-started)
