package com.smartclassroom.smart_classroom

import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.SystemClock
import androidx.core.app.NotificationCompat

/**
 * MonitoringService — Dedicated Android Foreground Service for screen monitoring.
 *
 * Timer Design:
 *  - Timer ONLY runs while the screen is ON (started on screen ON, stopped on screen OFF).
 *  - Uses a dedicated background HandlerThread — never blocks the main/UI thread.
 *  - Every 1 second: elapsedSeconds++
 *  - At elapsedSeconds >= 20: violation event fired, timer resets to 0, monitoring continues.
 *  - Screen OFF: timer stopped immediately, elapsedSeconds reset to 0.
 *  - START_STICKY + onTaskRemoved restart ensure service survives app swipe/close.
 */
class MonitoringService : Service() {

    companion object {
        const val NOTIFICATION_SERVICE_ID    = 1001
        const val CHANNEL_SERVICE            = "smart_monitor_service"
        const val CHANNEL_VIOLATION          = "smart_monitor_violation"
        const val VIOLATION_THRESHOLD        = 20   // seconds

        /** True while the service is running — read by MainActivity.isMonitoring. */
        @Volatile var isRunning = false
    }

    // ── Background HandlerThread — all timer work runs here, never on main thread ──
    private lateinit var timerThread: HandlerThread
    private lateinit var timerHandler: Handler

    // ── State ─────────────────────────────────────────────────────────────────
    @Volatile private var elapsedSeconds  = 0
    @Volatile private var timerRunning    = false
    private var violationCounter          = 0
    private var graceActive               = true   // ignore first stale screenOff at startup

    // ── 1-second tick Runnable (runs on timerHandler, not main thread) ────────
    private val tickRunnable = object : Runnable {
        override fun run() {
            elapsedSeconds++

            if (elapsedSeconds >= VIOLATION_THRESHOLD) {
                // ── Violation event ──────────────────────────────────────────
                onViolationDetected()
                elapsedSeconds = 0          // reset and keep monitoring
            }

            // Re-schedule next tick only if timer is still supposed to be running
            if (timerRunning) {
                timerHandler.postDelayed(this, 1_000)
            }
        }
    }

    // ── BroadcastReceiver for screen ON / OFF / UNLOCK ────────────────────────
    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {

                // Screen turned on OR user dismissed the lock screen
                Intent.ACTION_SCREEN_ON,
                Intent.ACTION_USER_PRESENT -> {
                    startScreenTimer()
                    refreshServiceNotification("Screen ON – monitoring active")
                }

                // Screen turned off (lock button or timeout)
                Intent.ACTION_SCREEN_OFF -> {
                    if (graceActive) return     // discard stale event fired at startup
                    stopScreenTimer()
                    refreshServiceNotification("Screen OFF – monitoring")
                }
            }
        }
    }

    // ── Timer helpers ─────────────────────────────────────────────────────────

    /**
     * Start (or restart) the 1-second background timer.
     * Resets elapsedSeconds to 0 every time the screen turns ON.
     */
    private fun startScreenTimer() {
        stopScreenTimer()           // cancel any pending tick first
        elapsedSeconds  = 0
        timerRunning    = true
        timerHandler.postDelayed(tickRunnable, 1_000)
    }

    /**
     * Stop the timer immediately and reset the counter.
     * Called when screen turns OFF or the service is destroyed.
     */
    private fun stopScreenTimer() {
        timerRunning = false
        timerHandler.removeCallbacks(tickRunnable)
        elapsedSeconds = 0
    }

    // ── Violation event ───────────────────────────────────────────────────────

    /**
     * Called when elapsedSeconds reaches the threshold.
     * Fires the violation notification; timer resets and continues automatically.
     */
    private fun onViolationDetected() {
        violationCounter++
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notification = NotificationCompat.Builder(this, CHANNEL_VIOLATION)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("⚠️  RULE BROKEN")
            .setContentText("20 seconds exceeded – Put your phone down!")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setVibrate(longArrayOf(0, 400, 200, 400))
            .build()
        // Each violation gets a unique ID so all appear in the notification shade
        nm.notify(2000 + violationCounter, notification)
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        isRunning = true

        // Start background thread for all timer work
        timerThread = HandlerThread("ScreenMonitorTimer").also { it.start() }
        timerHandler = Handler(timerThread.looper)

        createNotificationChannels()

        startForeground(
            NOTIFICATION_SERVICE_ID,
            buildServiceNotification("Smart Monitoring Active", "Initialising screen monitor…")
        )

        // Register receiver for screen events
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        registerReceiver(screenReceiver, filter)

        // After 3 s the startup grace period ends; start timer assuming screen is ON
        Handler(timerThread.looper).postDelayed({
            graceActive = false
            startScreenTimer()      // screen is ON when the student just opened the app
            refreshServiceNotification("Screen ON – monitoring active")
        }, 3_000)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int =
        START_STICKY    // OS will restart this service if it is killed

    /**
     * App swiped from Recents → schedule a 1-second restart via AlarmManager
     * so monitoring survives task removal.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        val restart = Intent(applicationContext, MonitoringService::class.java)
        val pi = PendingIntent.getService(
            this, 1, restart,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )
        (getSystemService(Context.ALARM_SERVICE) as AlarmManager).set(
            AlarmManager.ELAPSED_REALTIME,
            SystemClock.elapsedRealtime() + 1_000,
            pi
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        stopScreenTimer()
        timerThread.quitSafely()
        try { unregisterReceiver(screenReceiver) } catch (_: Exception) {}
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Notification helpers ──────────────────────────────────────────────────

    private fun createNotificationChannels() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        NotificationChannel(CHANNEL_SERVICE, "Monitoring Service", NotificationManager.IMPORTANCE_LOW)
            .apply {
                description = "Persistent notification while monitoring is active"
                setShowBadge(false)
            }.also { nm.createNotificationChannel(it) }

        NotificationChannel(CHANNEL_VIOLATION, "Screen Violations", NotificationManager.IMPORTANCE_HIGH)
            .apply {
                description = "Alert when screen usage exceeds 20 seconds"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 400, 200, 400)
                enableLights(true)
                lightColor = Color.RED
            }.also { nm.createNotificationChannel(it) }
    }

    private fun buildServiceNotification(title: String, text: String): Notification =
        NotificationCompat.Builder(this, CHANNEL_SERVICE)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)           // user cannot swipe this away
            .setShowWhen(false)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()

    private fun refreshServiceNotification(text: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_SERVICE_ID, buildServiceNotification("Smart Monitoring Active", text))
    }
}
