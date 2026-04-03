import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_config.dart';

class AlertDeliveryService {
  AlertDeliveryService._();
  static final AlertDeliveryService instance = AlertDeliveryService._();

  static String get _notifyAdminsUrl => AppConfig.notifyAdminsEndpoint;
  static const _retryQueueKey = 'pending_sms_alerts_v1';
  static const _cachedAdminPhoneKey = 'cached_admin_phone_v1';

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> handleViolationAlert({
    required String violationId,
    required String studentUID,
    required String studentName,
    required String regNo,
    required int secondsUsed,
  }) async {
    try {
      await _retryPendingSmsAlerts();
      await _ensureDefaultSettings();

      final settings = await _loadAlertSettings();
      if (secondsUsed < settings.usageLimit) {
        debugPrint(
          '[Alerts] usage below threshold: $secondsUsed < ${settings.usageLimit}',
        );
        await _markViolationAlertState(
          violationId: violationId,
          alertTriggered: false,
          alertType: 'NONE',
          alertStatus: 'usage_below_limit',
        );
        return;
      }

      final cooldownBlocked = await _isInCooldown(
        studentUID: studentUID,
        cooldownSeconds: settings.cooldownTime,
      );

      if (cooldownBlocked) {
        debugPrint('[Alerts] cooldown active; skipping alert for $studentUID');
        await _markViolationAlertState(
          violationId: violationId,
          alertTriggered: false,
          alertType: 'NONE',
          alertStatus: 'cooldown_skip',
        );
        return;
      }

      final internetAvailable = await _hasInternet();
      final alertTime = DateTime.now();
      final timeText = _formatAlertTime(alertTime);
      final alertMessage =
        'Alert: $studentName using mobile phone for $secondsUsed seconds at $timeText';

      String type = 'FCM';
      String status = 'sent';
      String targetPhone = '';

      if (internetAvailable) {
        final fcmOk = await _sendFcmToAdmins(
          studentName: studentName,
          regNo: regNo,
          secondsUsed: secondsUsed,
        );

        if (!fcmOk) {
          final resolvedPhone = await _getAdminPhone() ?? '';
          final smsResult = await _sendSmsFallback(
            preferredPhone: resolvedPhone,
            body: alertMessage,
            fallbackToQueueOnFailure: true,
          );
          type = 'SMS';
          status = smsResult;
          targetPhone = resolvedPhone;
        }
      } else {
        final resolvedPhone = await _getAdminPhone() ?? '';
        final smsResult = await _sendSmsFallback(
          preferredPhone: resolvedPhone,
          body: alertMessage,
          fallbackToQueueOnFailure: true,
        );
        type = 'SMS';
        status = smsResult;
        targetPhone = resolvedPhone;
      }

      await _storeAlert(
        studentUID: studentUID,
        name: studentName,
        type: type,
        status: status,
        secondsUsed: secondsUsed,
        internetAvailable: internetAvailable,
        targetPhone: targetPhone,
      );

      await _markViolationAlertState(
        violationId: violationId,
        alertTriggered: true,
        alertType: type,
        alertStatus: status,
      );
    } catch (e) {
      debugPrint('[Alerts] ❌ handleViolationAlert failed: $e');
      await _markViolationAlertState(
        violationId: violationId,
        alertTriggered: false,
        alertType: 'NONE',
        alertStatus: 'failed_internal',
      );
    }
  }

  Future<void> _markViolationAlertState({
    required String violationId,
    required bool alertTriggered,
    required String alertType,
    required String alertStatus,
  }) async {
    try {
      await _db.collection('violations').doc(violationId).set({
        'alertTriggered': alertTriggered,
        'alertType': alertType,
        'alertStatus': alertStatus,
        'alertUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Alerts] Failed to update violation alert state: $e');
    }
  }

  Future<void> _ensureDefaultSettings() async {
    try {
      await _db.collection('settings').doc('config').set({
        'usageLimit': 20,
        'cooldownTime': 60,
      }, SetOptions(merge: true));
    } catch (_) {
      // Ignore settings bootstrap failures; fallback defaults are used.
    }
  }

  Future<_AlertSettings> _loadAlertSettings() async {
    try {
      final snap = await _db.collection('settings').doc('config').get();
      final usage = (snap.data()?['usageLimit'] as num?)?.toInt() ?? 20;
      final cooldown = (snap.data()?['cooldownTime'] as num?)?.toInt() ?? 60;
      return _AlertSettings(usageLimit: usage, cooldownTime: cooldown);
    } catch (_) {
      return const _AlertSettings(usageLimit: 20, cooldownTime: 60);
    }
  }

  Future<bool> _isInCooldown({
    required String studentUID,
    required int cooldownSeconds,
  }) async {
    try {
      final snapshot = await _db
          .collection('alerts')
          .where('studentUID', isEqualTo: studentUID)
          .orderBy('lastSentTime', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return false;

      final lastSentTs = snapshot.docs.first.data()['lastSentTime'];
      if (lastSentTs is! Timestamp) return false;

      final elapsed = DateTime.now().difference(lastSentTs.toDate()).inSeconds;
      return elapsed < cooldownSeconds;
    } catch (e) {
      debugPrint('[Alerts] cooldown query failed, skipping cooldown: $e');
      return false;
    }
  }

  Future<bool> _hasInternet() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        return false;
      }

      final result = await InternetAddress.lookup('firebase.google.com');
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _sendFcmToAdmins({
    required String studentName,
    required String regNo,
    required int secondsUsed,
  }) async {
    final timeText = _formatAlertTime(DateTime.now());
    final bodyText = regNo.trim().isEmpty
      ? '$studentName used phone for ${secondsUsed}s at $timeText.'
      : '$studentName ($regNo) used phone for ${secondsUsed}s at $timeText.';

    final payload = {
      'title': 'Violation Detected',
      'body': bodyText,
      'data': {
        'type': 'violation',
        'studentName': studentName,
        'regNo': regNo,
        'secondsUsed': secondsUsed.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      },
    };

    try {
      final response = await http
          .post(
            Uri.parse(_notifyAdminsUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(response.body);
      return decoded is Map && decoded['success'] == true;
    } catch (e) {
      debugPrint('[Alerts] FCM request failed: $e');
      return false;
    }
  }

  Future<String> _sendSmsFallback({
    String? preferredPhone,
    required String body,
    required bool fallbackToQueueOnFailure,
  }) async {
    final rawPhone = (preferredPhone ?? '').trim().isNotEmpty
        ? preferredPhone!.trim()
        : await _getAdminPhone();
    final phone = _normalizePhone(rawPhone);
    if (phone == null || phone.isEmpty) {
      return 'failed_no_phone';
    }

    if (!_looksValidPhone(phone)) {
      return 'failed_invalid_phone';
    }

    final status = await Permission.sms.request();
    if (!status.isGranted) {
      if (fallbackToQueueOnFailure) {
        await _enqueuePendingSms(phone: phone, body: body);
      }
      if (status.isPermanentlyDenied) return 'failed_sms_perm_permanently_denied';
      if (status.isRestricted) return 'failed_sms_perm_restricted';
      return 'failed_sms_perm_denied';
    }

    try {
      await sendSMS(message: body, recipients: [phone]);
      return 'sent';
    } catch (e) {
      debugPrint('[Alerts] SMS send failed, queued: $e');
      if (fallbackToQueueOnFailure) {
        await _enqueuePendingSms(phone: phone, body: body);
      }
      return 'queued';
    }
  }

  Future<String?> _getAdminPhone() async {
    try {
      final snap = await _db.collection('admins').doc('admin1').get();
      final directPhone = _extractAdminPhone(snap.data());
      if (directPhone.isNotEmpty) {
        await _cacheAdminPhone(directPhone);
        return directPhone;
      }

      final byRole = await _db
          .collection('admins')
          .where('role', isEqualTo: 'admin')
          .limit(1)
          .get();
      if (byRole.docs.isNotEmpty) {
        final rolePhone = _extractAdminPhone(byRole.docs.first.data());
        if (rolePhone.isNotEmpty) {
          await _cacheAdminPhone(rolePhone);
          return rolePhone;
        }
      }

      // Final DB fallback: scan a few admin docs and pick first valid phone.
      final anyAdmin = await _db.collection('admins').limit(10).get();
      for (final doc in anyAdmin.docs) {
        final phone = _extractAdminPhone(doc.data());
        if (phone.isNotEmpty) {
          await _cacheAdminPhone(phone);
          return phone;
        }
      }
    } catch (_) {
      // ignore and fallback to cached value
    }

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cachedAdminPhoneKey) ?? '';
    return cached.trim().isEmpty ? null : cached.trim();
  }

  Future<void> _cacheAdminPhone(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedAdminPhoneKey, phone);
  }

  String _extractAdminPhone(Map<String, dynamic>? data) {
    if (data == null) return '';
    const keys = ['phone', 'mobile', 'phoneNumber', 'contactNumber'];
    for (final key in keys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String? _normalizePhone(String? value) {
    final input = (value ?? '').trim();
    if (input.isEmpty) return null;

    if (input.startsWith('+')) {
      final plusNormalized = '+${input.substring(1).replaceAll(RegExp(r'[^0-9]'), '')}';
      return plusNormalized;
    }

    return input.replaceAll(RegExp(r'[^0-9]'), '');
  }

  bool _looksValidPhone(String phone) {
    final digitsOnly = phone.startsWith('+') ? phone.substring(1) : phone;
    return digitsOnly.length >= 10;
  }

  Future<void> _storeAlert({
    required String studentUID,
    required String name,
    required String type,
    required String status,
    required int secondsUsed,
    required bool internetAvailable,
    String targetPhone = '',
  }) async {
    final now = DateTime.now();

    await _db.collection('alerts').add({
      'studentUID': studentUID,
      'name': name,
      'type': type,
      'status': status,
      'secondsUsed': secondsUsed,
      'internetAvailable': internetAvailable,
      'targetPhone': targetPhone,
      'smsAttempted': type == 'SMS',
      'timestamp': FieldValue.serverTimestamp(),
      'lastSentTime': Timestamp.fromDate(now),
    });
  }

  Future<void> _retryPendingSmsAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_retryQueueKey);
    if (raw == null || raw.isEmpty) return;

    final decoded = jsonDecode(raw);
    if (decoded is! List) return;

    final remaining = <Map<String, String>>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final phone = (item['phone'] ?? '').toString().trim();
      final body = (item['body'] ?? '').toString().trim();
      if (body.isEmpty) continue;

      try {
        final smsStatus = await _sendSmsFallback(
          preferredPhone: phone,
          body: body,
          fallbackToQueueOnFailure: false,
        );
        if (smsStatus != 'sent') {
          remaining.add({'phone': phone, 'body': body});
        }
      } catch (_) {
        remaining.add({'phone': phone, 'body': body});
      }
    }

    await prefs.setString(_retryQueueKey, jsonEncode(remaining));
  }

  Future<void> _enqueuePendingSms({
    required String phone,
    required String body,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_retryQueueKey);

    final queue = <Map<String, String>>[];
    if (raw != null && raw.isNotEmpty) {
      final parsed = jsonDecode(raw);
      if (parsed is List) {
        for (final entry in parsed) {
          if (entry is Map) {
            queue.add({
              'phone': (entry['phone'] ?? '').toString(),
              'body': (entry['body'] ?? '').toString(),
            });
          }
        }
      }
    }

    queue.add({'phone': phone, 'body': body});
    await prefs.setString(_retryQueueKey, jsonEncode(queue));
  }

  String _formatAlertTime(DateTime dateTime) {
    final hh = dateTime.hour.toString().padLeft(2, '0');
    final mm = dateTime.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _AlertSettings {
  const _AlertSettings({required this.usageLimit, required this.cooldownTime});

  final int usageLimit;
  final int cooldownTime;
}
