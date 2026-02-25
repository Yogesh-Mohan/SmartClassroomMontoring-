package com.smartclassroom.smart_classroom

import android.app.AppOpsManager
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity — Exposes a MethodChannel so Flutter can start/stop
 * the native MonitoringService without depending on any plugin.
 *
 * Channel: com.smartclassroom.smart_classroom/monitoring
 * Methods:
 *   startMonitoring() -> bool
 *   stopMonitoring()  -> bool
 *   isMonitoring()    -> bool
 */
class MainActivity : FlutterActivity() {

    private val channel = "com.smartclassroom.smart_classroom/monitoring"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
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
                        // Opens the Usage Access settings screen for the user to grant permission
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(null)
                    }
                    "updateTimetableStatus" -> {
                        val active = call.argument<Boolean>("active") ?: false
                        MonitoringService.monitoringActive = active
                        MonitoringService.lastTimetablePushMs = System.currentTimeMillis()
                        result.success(null)
                    }
                    "updateTimetableDebug" -> {
                        val info = call.argument<String>("info") ?: ""
                        MonitoringService.dartDebugInfo = info
                        result.success(null)
                    }
                    else -> result.notImplemented()
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

    /**
     * Returns true if the app has been granted Usage Access (PACKAGE_USAGE_STATS).
     * This is a special permission — the user must manually enable it in Settings.
     */
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
