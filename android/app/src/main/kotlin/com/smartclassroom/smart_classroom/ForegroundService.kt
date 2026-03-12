package com.smartclassroom.smart_classroom

import android.app.*
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.pm.ApplicationInfo
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

class MonitoringService : Service() {

    companion object {
        const val NOTIFICATION_SERVICE_ID = 1001
        const val CHANNEL_SERVICE         = "smart_monitor_service"
        const val CHANNEL_VIOLATION       = "smart_monitor_violation"
        const val VIOLATION_THRESHOLD     = 20
        const val ACTIVE_CHECK_INTERVAL_MS = 1_000L
        const val PASSIVE_CHECK_INTERVAL_MS = 10_000L

        @Volatile var isRunning = false

        /**
         * Timetable gate — set by Flutter (Dart) via MethodChannel.
         * true  = current time is inside a class period with monitoring == true
         * false = break time, after hours, or timetable not yet loaded
         * Default false: monitoring does NOT run until Dart confirms a class period.
         */
        @Volatile var monitoringActive = false

        /**
         * Admin master switch — set by admin from the Live Monitoring screen.
         * When false → NO timer counting, NO violations, even during class time.
         * Default true: monitoring is ON by default when class starts.
         */
        @Volatile var adminMonitoringEnabled = true

        /** Epoch millis of the last updateTimetableStatus call from Dart. */
        @Volatile var lastTimetablePushMs = 0L

        /** Debug string sent by the Dart TimetableMonitor. */
        @Volatile var dartDebugInfo = ""

        /** Current active period doc ID (e.g. "peroid 3") sent by TimetableMonitor. */
        @Volatile var currentPeriod = ""

        /**
         * MethodChannel instance held by MainActivity so the service can
         * send violation events back to Flutter without needing a context reference.
         */
        @Volatile var flutterChannel: io.flutter.plugin.common.MethodChannel? = null

        val BLOCKED_APPS: Set<String> = setOf(
            // Social Media
            "com.instagram.android", "com.facebook.katana", "com.facebook.lite",
            "com.twitter.android", "com.twitter.android.lite",
            "com.snapchat.android", "com.whatsapp", "com.whatsapp.w4b",
            "org.telegram.messenger", "com.zhiliaoapp.musically",
            "com.ss.android.ugc.trill", "com.pinterest", "com.reddit.frontpage",
            "com.linkedin.android", "com.tumblr", "com.discord",
            "com.sharechat.app", "com.imo.android.imoim",
            // Video Streaming
            "com.google.android.youtube", "com.netflix.mediaclient",
            "com.amazon.avod.thirdpartyclient", "in.startv.hotstar",
            "com.disney.disneyplus", "tv.twitch.android.app",
            "com.facebook.orca", "com.vanced.android.youtube",
            "app.revanced.android.youtube", "com.zee5", "com.voot.app",
            "com.jio.jioplay.tv", "com.mxtech.videoplayer.ad",
            // Games
            "com.supercell.clashofclans", "com.supercell.clashroyale",
            "com.supercell.brawlstars", "com.king.candycrushsaga",
            "com.activision.callofduty.shooter", "com.garena.game.freefire",
            "com.pubg.imobile", "com.tencent.ig", "com.kiloo.subwaysurf",
            "com.outfit7.talkingtom2", "com.mojang.minecraftpe",
            "com.roblox.client", "com.ea.game.pvzfree_row",
            "com.garena.game.codm", "com.imangi.templerun2",
            "com.miniclip.eightballpool",
            // Browsers
            "com.android.chrome", "org.mozilla.firefox",
            "com.opera.browser", "com.opera.mini.native",
            "com.microsoft.emmx", "com.brave.browser",
            "com.UCMobile.intl", "com.duckduckgo.mobile.android",
            "com.kiwibrowser.browser", "com.uc.browser.en"
        )
    }

    private lateinit var timerThread: HandlerThread
    private lateinit var timerHandler: Handler

    @Volatile private var isScreenOn     = true
    @Volatile private var elapsedSeconds = 0
    @Volatile private var timerRunning   = false

    private var violationCounter  = 0
    private var graceActive       = true
    private var lastDetectedApp   = "__init__"
    private var currentMode       = "sleep" // sleep | passive | active

    private fun resetSession() {
        elapsedSeconds = 0
        lastDetectedApp = "__init__"
        timerRunning = false
    }

    //  1-second tick loop 
    private val tickRunnable = object : Runnable {
        override fun run() {
            val timetableOn = monitoringActive
            val monitoringAllowed = timetableOn && adminMonitoringEnabled

            if (!isScreenOn) {
                currentMode = "sleep"
                resetSession()
                refreshServiceNotification("Smart Classroom", "Screen OFF - monitoring sleep mode")
                sendLiveUpdateToFlutter("", 0, timetableOn, currentMode)
                timerHandler.postDelayed(this, PASSIVE_CHECK_INTERVAL_MS)
                return
            }

            val currentApp = getCurrentForegroundApp()
            val interactiveApp = isBlockedApp(currentApp)
            val systemApp = isSystemApp(currentApp)
            val nextMode = if (monitoringAllowed && interactiveApp) "active" else "passive"
            val appChanged = currentApp != lastDetectedApp

            if (nextMode != currentMode) {
                currentMode = nextMode
                if (currentMode != "active") {
                    resetSession()
                }
            }

            if (currentMode == "active") {
                if (appChanged) {
                    lastDetectedApp = currentApp
                    elapsedSeconds = 0
                }
                timerRunning = true
                elapsedSeconds++

                refreshServiceNotification(
                    "\uD83D\uDD35 Class Time — Active Monitoring",
                    "${elapsedSeconds}s / ${VIOLATION_THRESHOLD}s on ${friendlyAppName(currentApp)}"
                )

                if (elapsedSeconds > VIOLATION_THRESHOLD) {
                    fireViolationNotification(elapsedSeconds)
                    // Requirement: reset timer once violation is detected.
                    elapsedSeconds = 0
                }

                sendLiveUpdateToFlutter(currentApp, elapsedSeconds, timetableOn, currentMode)
                timerHandler.postDelayed(this, ACTIVE_CHECK_INTERVAL_MS)
                return
            }

            // Passive mode: non-interactive app, system app, break-time, or admin pause.
            timerRunning = false
            elapsedSeconds = 0
            lastDetectedApp = currentApp

            val passiveText = when {
                !monitoringAllowed -> "Monitoring paused (break/admin)"
                systemApp -> "System app detected: ${friendlyAppName(currentApp)}"
                currentApp.isNotEmpty() -> "Passive app detected: ${friendlyAppName(currentApp)}"
                else -> "Passive mode"
            }

            refreshServiceNotification("\uD83D\uDFE1 Passive Monitoring", passiveText)
            sendLiveUpdateToFlutter(currentApp, 0, timetableOn, currentMode)
            timerHandler.postDelayed(this, PASSIVE_CHECK_INTERVAL_MS)
        }
    }

    //  Screen ON / OFF receiver 
    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_ON,
                Intent.ACTION_USER_PRESENT -> {
                    isScreenOn      = true
                    resetSession()
                    refreshServiceNotification("Smart Classroom", "Screen ON - detecting app...")
                }
                Intent.ACTION_SCREEN_OFF -> {
                    if (graceActive) return
                    isScreenOn      = false
                    currentMode = "sleep"
                    resetSession()
                    refreshServiceNotification("Smart Classroom", "Screen OFF - monitoring paused")
                }
            }
        }
    }

    //  Foreground app detection via UsageStatsManager 
    private fun getCurrentForegroundApp(): String {
        return try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val now = System.currentTimeMillis()
            // 20-minute window: catches app opened before service started
            val events = usm.queryEvents(now - 1_200_000, now)
            val event  = UsageEvents.Event()
            var lastPkg  = ""
            var lastTime = 0L
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND &&
                    event.timeStamp > lastTime) {
                    lastPkg  = event.packageName
                    lastTime = event.timeStamp
                }
            }
            lastPkg
        } catch (e: Exception) { "" }
    }

    private fun isBlockedApp(pkg: String): Boolean {
        if (pkg.isEmpty()) return false  // unknown app = safe, do NOT count
        return pkg in BLOCKED_APPS
    }

    private fun isSystemApp(pkg: String): Boolean {
        if (pkg.isEmpty()) return false
        if (pkg == "android" || pkg == "com.android.systemui" || pkg.startsWith("com.android.")) {
            return true
        }
        return try {
            val appInfo = packageManager.getApplicationInfo(pkg, 0)
            (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
                (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
        } catch (_: Exception) {
            false
        }
    }

    private fun friendlyAppName(pkg: String): String {
        if (pkg.isBlank()) return "Unknown"
        return when (pkg) {
            "com.whatsapp" -> "WhatsApp"
            "com.instagram.android" -> "Instagram"
            "com.android.chrome" -> "Chrome"
            "com.google.android.youtube" -> "YouTube"
            "com.android.settings" -> "Settings"
            "com.android.systemui" -> "System UI"
            else -> pkg.substringAfterLast('.')
        }
    }

    //  Lifecycle 
    override fun onCreate() {
        super.onCreate()
        isRunning = true

        timerThread  = HandlerThread("SCMonitorThread").also { it.start() }
        timerHandler = Handler(timerThread.looper)

        createNotificationChannels()
        startForeground(
            NOTIFICATION_SERVICE_ID,
            buildServiceNotification("Smart Classroom", "Starting...")
        )

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        registerReceiver(screenReceiver, filter)

        // 1-second grace, then start tick loop
        timerHandler.postDelayed({
            graceActive = false
            timerHandler.post(tickRunnable)
        }, 1_000)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        val pi = PendingIntent.getService(
            this, 1,
            Intent(applicationContext, MonitoringService::class.java),
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        )
        (getSystemService(Context.ALARM_SERVICE) as AlarmManager).set(
            AlarmManager.ELAPSED_REALTIME,
            SystemClock.elapsedRealtime() + 1_000, pi
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        timerHandler.removeCallbacksAndMessages(null)
        timerThread.quitSafely()
        try { unregisterReceiver(screenReceiver) } catch (_: Exception) {}
    }

    override fun onBind(intent: Intent?): IBinder? = null

    //  Notifications 
    private fun fireViolationNotification(secondsUsed: Int) {
        violationCounter++

        // 1. Show local notification
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(
            2000 + violationCounter,
            NotificationCompat.Builder(this, CHANNEL_VIOLATION)
                .setSmallIcon(R.mipmap.kr_launcher_new)
                .setContentTitle("RULE BROKEN")
                .setContentText("${secondsUsed}s of screen time exceeded! Put your phone down.")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setVibrate(longArrayOf(0, 400, 200, 400))
                .build()
        )

        // 2. Callback Flutter so it can save to Firestore
        val channel = flutterChannel
        if (channel != null) {
            val args = mapOf(
                "secondsUsed" to secondsUsed,
                "period"      to currentPeriod
            )
            // Must run on the main thread for Flutter MethodChannel
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                channel.invokeMethod("onViolation", args)
            }
        } else {
            android.util.Log.w("MonitoringService", "flutterChannel is null — violation NOT sent to Flutter")
        }
    }

    /**
     * Send live monitoring data to Flutter so it can be pushed to Firestore
     * for the admin real-time dashboard.
     *
     * status:
     *   "active"  → student is currently using an interactive app during class
     *   "idle"    → screen off, no interactive app, or break time
     *   "offline" → set by Flutter when the student logs out
     */
    private fun sendLiveUpdateToFlutter(currentApp: String, screenTime: Int, monitoringOn: Boolean, mode: String) {
        val channel = flutterChannel ?: return

        val status = when {
            !isScreenOn  -> "idle"
            mode == "active" -> "active"
            else -> "idle"
        }

        val reportedApp = if (currentApp.isBlank()) "" else currentApp

        val args = mapOf(
            "currentApp"    to reportedApp,
            "screenTime"    to screenTime,
            "period"        to currentPeriod,
            "monitoringOn"  to monitoringOn,
            "status"        to status,
            "mode"          to mode
        )
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            channel.invokeMethod("onLiveUpdate", args)
        }
    }

    private fun createNotificationChannels() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_SERVICE, "Monitoring Service",
                NotificationManager.IMPORTANCE_LOW).apply {
                description = "Persistent monitoring indicator"
                setShowBadge(false)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_VIOLATION, "Screen Violations",
                NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Alert when screen usage exceeds 20 seconds"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 400, 200, 400)
                enableLights(true)
                lightColor = Color.RED
            }
        )
    }

    private fun buildServiceNotification(title: String, text: String): Notification =
        NotificationCompat.Builder(this, CHANNEL_SERVICE)
            .setSmallIcon(R.mipmap.kr_launcher_new)
            .setContentTitle(title)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setShowWhen(false)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()

    private fun refreshServiceNotification(title: String, text: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_SERVICE_ID,
            buildServiceNotification(title, text))
    }
}