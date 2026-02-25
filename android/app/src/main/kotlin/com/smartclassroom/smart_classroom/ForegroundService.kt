package com.smartclassroom.smart_classroom

import android.app.*
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
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

        @Volatile var isRunning = false

        /**
         * Timetable gate — set by Flutter (Dart) via MethodChannel.
         * true  = current time is inside a class period with monitoring == true
         * false = break time, after hours, or timetable not yet loaded
         * Default false: monitoring does NOT run until Dart confirms a class period.
         */
        @Volatile var monitoringActive = false

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
    private var lastMonitorActive = false   // tracks previous monitoringActive state
    private var tickCount         = 0

    //  1-second tick loop 
    private val tickRunnable = object : Runnable {
        override fun run() {
            tickCount++

            if (!isScreenOn) {
                timerHandler.postDelayed(this, 1_000)
                return
            }

            val currentApp    = getCurrentForegroundApp()
            val isBlocked     = isBlockedApp(currentApp)
            val timetableOn   = monitoringActive
            val appChanged    = currentApp != lastDetectedApp
            val timetableFlip = timetableOn != lastMonitorActive
            val periodicRefresh = tickCount % 10 == 0  // refresh every 10s

            // Handle app switch or timetable state flip (or periodic refresh)
            if (appChanged || timetableFlip || periodicRefresh) {
                if (appChanged) {
                    lastDetectedApp = currentApp
                    elapsedSeconds  = 0
                }
                lastMonitorActive = timetableOn

                when {
                    // Class in session + blocked app in foreground -> start/resume timer
                    isBlocked && timetableOn -> {
                        timerRunning = true
                        refreshServiceNotification(
                            "\uD83D\uDD35 Class Time — Monitoring ON",
                            "Monitoring: ${elapsedSeconds}s / 20s"
                        )
                    }
                    // Blocked app but outside class period -> break time gate
                    isBlocked && !timetableOn -> {
                        timerRunning   = false
                        elapsedSeconds = 0
                        refreshServiceNotification(
                            "\uD83D\uDFE0 Break Time",
                            "Monitoring is OFF during break"
                        )
                    }
                    // Non-blocked (system/study) app -> always pause
                    else -> {
                        timerRunning   = false
                        elapsedSeconds = 0
                        val body = if (timetableOn)
                            "Class time — studying detected"
                        else
                            "Break time — monitoring OFF"
                        refreshServiceNotification(
                            if (timetableOn) "\uD83D\uDD35 Class Time" else "\uD83D\uDFE0 Break Time",
                            body
                        )
                    }
                }
            }

            // Count seconds: ALL THREE must be true
            if (timerRunning && isBlocked && timetableOn) {
                elapsedSeconds++
                refreshServiceNotification(
                    "\uD83D\uDD35 Class Time — Monitoring ON",
                    "${elapsedSeconds}s / ${VIOLATION_THRESHOLD}s on restricted app"
                )
                if (elapsedSeconds >= VIOLATION_THRESHOLD) {
                    fireViolationNotification(elapsedSeconds)
                    elapsedSeconds = 0
                }
            }

            timerHandler.postDelayed(this, 1_000)
        }
    }

    //  Screen ON / OFF receiver 
    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_ON,
                Intent.ACTION_USER_PRESENT -> {
                    isScreenOn      = true
                    elapsedSeconds  = 0
                    lastDetectedApp = "__init__"
                    timerRunning    = false
                    refreshServiceNotification("Smart Classroom", "Screen ON - detecting app...")
                }
                Intent.ACTION_SCREEN_OFF -> {
                    if (graceActive) return
                    isScreenOn      = false
                    timerRunning    = false
                    elapsedSeconds  = 0
                    lastDetectedApp = "__init__"
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
        if (pkg.isEmpty()) return true
        return pkg in BLOCKED_APPS
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
                .setSmallIcon(R.mipmap.ic_launcher)
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
            .setSmallIcon(R.mipmap.ic_launcher)
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