package com.smartclassroom.smart_classroom

import android.Manifest
import android.app.AppOpsManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channel = "com.smartclassroom.smart_classroom/monitoring"
    private val SMS_PERMISSION_CODE = 101

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
        MonitoringService.flutterChannel = methodChannel

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {

                "startMonitoring" -> {
                    startNativeService()
                    result.success(true)
                }

                "stopMonitoring" -> {
                    stopService(Intent(this, MonitoringService::class.java))
                    result.success(true)
                }

                "isMonitoring" -> {
                    result.success(MonitoringService.isRunning)
                }

                "hasUsagePermission" -> {
                    result.success(hasUsageStatsPermission())
                }

                "requestUsagePermission" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(null)
                }

                "updateTimetableStatus" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    val period = call.argument<String>("period") ?: ""
                    MonitoringService.monitoringActive = active
                    MonitoringService.lastTimetablePushMs = System.currentTimeMillis()
                    if (period.isNotEmpty()) MonitoringService.currentPeriod = period
                    result.success(null)
                }

                "updateTimetableDebug" -> {
                    val info = call.argument<String>("info") ?: ""
                    MonitoringService.dartDebugInfo = info
                    result.success(null)
                }

                "setAdminMonitoring" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    MonitoringService.adminMonitoringEnabled = enabled
                    result.success(null)
                }

                // ── NEW: Flutter pushes admin phone number from Firestore ──────
                "setAdminPhone" -> {
                    val phone = call.argument<String>("phone") ?: ""
                    MonitoringService.adminPhoneNumber = phone.trim()
                    android.util.Log.d("MainActivity", "Admin phone set: ${MonitoringService.adminPhoneNumber}")
                    result.success(null)
                }

                "setStudentIdentity" -> {
                    val name = call.argument<String>("studentName") ?: "Student"
                    val regNo = call.argument<String>("regNo") ?: ""
                    MonitoringService.studentNameForAlerts = name.trim().ifEmpty { "Student" }
                    MonitoringService.studentRegNoForAlerts = regNo.trim()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        requestSmsPermissionIfNeeded()
    }

    // Request SMS permission at runtime (Android 6+)
    private fun requestSmsPermissionIfNeeded() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS)
            != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.SEND_SMS),
                SMS_PERMISSION_CODE
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_PERMISSION_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                android.util.Log.d("MainActivity", "✅ SMS permission granted")
            } else {
                android.util.Log.w("MainActivity", "⚠️ SMS permission denied — offline alerts won't work")
            }
        }
    }

    private fun startNativeService() {
        val intent = Intent(this, MonitoringService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun hasUsageStatsPermission(): Boolean {
        return try {
            val appOps = getSystemService(APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }
}
