import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_config.dart';

class AlertDeliveryService {
  AlertDeliveryService._();
  static final AlertDeliveryService instance = AlertDeliveryService._();

  static String get _notifyAdminsUrl => AppConfig.notifyAdminsEndpoint;
  static const _pendingFcmQueueKey = 'pending_fcm_alerts_v1';

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> handleViolationAlert({
    required String violationId,
    required String studentUID,
    required String studentName,
    required String regNo,
    required int secondsUsed,
  }) async {
    try {
      await _retryPendingFcmAlerts();
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
          type = 'FCM';
          status = 'failed_fcm';
          await _enqueuePendingFcmAlert(
            violationId: violationId,
            studentName: studentName,
            regNo: regNo,
            secondsUsed: secondsUsed,
          );
        }
      } else {
        // SMS is sent by native MonitoringService via SmsManager.
        // Keep this service focused on Firestore logging + FCM delivery.
        type = 'FCM';
        status = 'skipped_offline_native_sms';
        await _enqueuePendingFcmAlert(
          violationId: violationId,
          studentName: studentName,
          regNo: regNo,
          secondsUsed: secondsUsed,
        );
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

      final alertTriggered =
          status == 'sent' || status == 'skipped_offline_native_sms';
      if (alertTriggered) {
        await _updateCooldown(studentUID: studentUID);
      }

      await _markViolationAlertState(
        violationId: violationId,
        alertTriggered: alertTriggered,
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

  Future<void> syncPendingAlertsNow() async {
    await _retryPendingFcmAlerts();
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
      final cooldownDoc = await _db
          .collection('alert_cooldowns')
          .doc(studentUID)
          .get();

      final lastSentTs = cooldownDoc.data()?['lastSentTime'];
      if (lastSentTs is! Timestamp) return false;

      final elapsed = DateTime.now().difference(lastSentTs.toDate()).inSeconds;
      return elapsed < cooldownSeconds;
    } catch (e) {
      debugPrint('[Alerts] cooldown query failed, skipping cooldown: $e');
      return false;
    }
  }

  Future<void> _updateCooldown({required String studentUID}) async {
    try {
      await _db.collection('alert_cooldowns').doc(studentUID).set({
        'studentUID': studentUID,
        'lastSentTime': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[Alerts] Failed to update cooldown: $e');
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

  Future<void> _retryPendingFcmAlerts() async {
    if (!await _hasInternet()) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingFcmQueueKey);
    if (raw == null || raw.isEmpty) return;

    final parsed = jsonDecode(raw);
    if (parsed is! List) return;

    final remaining = <Map<String, dynamic>>[];
    for (final item in parsed) {
      if (item is! Map) continue;

      final violationId = (item['violationId'] ?? '').toString();
      final studentName = (item['studentName'] ?? 'Student').toString();
      final regNo = (item['regNo'] ?? '').toString();
      final secondsUsed = int.tryParse((item['secondsUsed'] ?? '0').toString()) ?? 0;

      final ok = await _sendFcmToAdmins(
        studentName: studentName,
        regNo: regNo,
        secondsUsed: secondsUsed,
      );

      if (ok) {
        if (violationId.isNotEmpty) {
          await _markViolationAlertState(
            violationId: violationId,
            alertTriggered: true,
            alertType: 'FCM',
            alertStatus: 'sent_delayed_online',
          );
        }
      } else {
        remaining.add({
          'violationId': violationId,
          'studentName': studentName,
          'regNo': regNo,
          'secondsUsed': secondsUsed,
        });
      }
    }

    await prefs.setString(_pendingFcmQueueKey, jsonEncode(remaining));
  }

  Future<void> _enqueuePendingFcmAlert({
    required String violationId,
    required String studentName,
    required String regNo,
    required int secondsUsed,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingFcmQueueKey);

    final queue = <Map<String, dynamic>>[];
    if (raw != null && raw.isNotEmpty) {
      final parsed = jsonDecode(raw);
      if (parsed is List) {
        for (final entry in parsed) {
          if (entry is Map) {
            queue.add({
              'violationId': (entry['violationId'] ?? '').toString(),
              'studentName': (entry['studentName'] ?? 'Student').toString(),
              'regNo': (entry['regNo'] ?? '').toString(),
              'secondsUsed': int.tryParse((entry['secondsUsed'] ?? '0').toString()) ?? 0,
            });
          }
        }
      }
    }

    final exists = queue.any((item) => item['violationId'] == violationId);
    if (!exists) {
      queue.add({
        'violationId': violationId,
        'studentName': studentName,
        'regNo': regNo,
        'secondsUsed': secondsUsed,
      });
    }

    await prefs.setString(_pendingFcmQueueKey, jsonEncode(queue));
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
      'smsAttempted': false,
      'timestamp': FieldValue.serverTimestamp(),
      'lastSentTime': Timestamp.fromDate(now),
    });
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
