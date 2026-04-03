import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Authentication Service
/// 
/// Provides common authentication utilities and Firebase Auth operations.
/// Handles user session management, token refresh, and auth state monitoring.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get current authenticated user
  User? get currentUser => _auth.currentUser;

  /// Check if user is currently logged in
  bool get isAuthenticated => currentUser != null;

  /// Get current user ID
  String? get currentUserId => currentUser?.uid;

  /// Get current user email
  String? get currentUserEmail => currentUser?.email;

  /// Stream of auth state changes
  /// 
  /// Emits User when user logs in/signs up, null when user logs out
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Stream of ID token changes
  /// 
  /// Useful for monitoring token refresh
  Stream<User?> idTokenChanges() => _auth.idTokenChanges();

  /// Sign out current user
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      debugPrint('[AuthService] User signed out successfully');
    } catch (e) {
      debugPrint('[AuthService] Sign out error: $e');
      rethrow;
    }
  }

  /// Get current user's ID token
  /// 
  /// Useful for passing to backend APIs
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    try {
      final token = await currentUser?.getIdToken(forceRefresh);
      return token;
    } catch (e) {
      debugPrint('[AuthService] Error getting ID token: $e');
      return null;
    }
  }

  /// Check if user's email is verified
  bool get isEmailVerified => currentUser?.emailVerified ?? false;

  /// Get user's authentication provider info
  /// 
  /// Returns list of provider IDs (e.g., 'password', 'google.com')
  List<String>? get providerIds => 
      currentUser?.providerData.map((provider) => provider.providerId).toList();

  /// Verify user's session is still valid on backend
  /// 
  /// Can be called periodically to ensure session hasn't been revoked
  Future<bool> verifySession() async {
    try {
      if (!isAuthenticated) {
        return false;
      }
      // Refresh ID token to validate session
      await getIdToken(forceRefresh: true);
      return true;
    } catch (e) {
      debugPrint('[AuthService] Session verification failed: $e');
      return false;
    }
  }
}
