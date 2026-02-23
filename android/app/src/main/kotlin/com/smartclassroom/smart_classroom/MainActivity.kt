package com.smartclassroom.smart_classroom

import android.content.Intent
import android.os.Build
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
}
