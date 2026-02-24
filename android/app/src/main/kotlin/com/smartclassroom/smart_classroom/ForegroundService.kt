package com.smartclassroom.smart_classroom

import android.app.*
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

/**
 * MonitoringService — Dedicated Android Foreground Service for screen monitoring.
 *
 * Design:
 *  - Uses UsageStatsManager to detect the foreground app every second.
 *  - Maintains a BLOCKED_APPS set (social media, streaming, games, browsers).
 *  - Timer runs ONLY when: screen is ON AND foreground app is in BLOCKED_APPS.
 *  - Timer stops and resets immediately when a system/non-blocked app comes to foreground.
 *  - Uses a dedicated HandlerThread — never blocks the main/UI thread.
 *  - START_STICKY + onTaskRemoved ensures the service survives app close/swipe.
 */
class MonitoringService : Service() {

    companion object {
        const val NOTIFICATION_SERVICE_ID = 1001
        const val CHANNEL_SERVICE         = "smart_monitor_service"
        const val CHANNEL_VIOLATION       = "smart_monitor_violation"
        const val VIOLATION_THRESHOLD     = 20   // seconds

        /** True while the service is running — read by MainActivity. */
        @Volatile var isRunning = false

        /**
         * Predefined list of user-interactive (distraction) app package names.
         * Timer only runs when one of these is in the foreground.
         */
        val BLOCKED_APPS: Set<String> = setOf(
            // ── Social Media ──────────────────────────────────────────────────
            "com.instagram.android",
            "com.facebook.katana",
            "com.facebook.lite",
            "com.twitter.android",
            "com.twitter.android.lite",
            "com.snapchat.android",
            "com.whatsapp",
            "com.whatsapp.w4b",
            "org.telegram.messenger",
            "com.zhiliaoapp.musically",    // TikTok
            "com.ss.android.ugc.trill",    // TikTok (some regions)
            "com.pinterest",
            "com.reddit.frontpage",
            "com.linkedin.android",
            "com.tumblr",
            "com.discord",

            // ── Video Streaming ───────────────────────────────────────────────
            "com.google.android.youtube",
            "com.netflix.mediaclient",
            "com.amazon.avod.thirdpartyclient",  // Prime Video
            "com.disney.disneyplus",
            "com.hotstar.android",
            "tv.twitch.android.app",
            "com.facebook.orca",            // Facebook Messenger
            "com.vanced.android.youtube",   // YouTube Vanced
            "app.revanced.android.youtube", // YouTube ReVanced

            // ── Games (common categories) ─────────────────────────────────────
            "com.supercell.clashofclans",
            "com.supercell.clashroyale",
            "com.supercell.brawlstars",
            "com.king.candycrushsaga",
            "com.activision.callofduty.shooter",
            "com.garena.game.freefire",
            "com.pubg.imobile",
            "com.tencent.ig",               // PUBG Mobile
            "com.kiloo.subwaysurf",
            "com.outfit7.talkingtom2",
            "com.mojang.minecraftpe",
            "com.roblox.client",
            "com.ea.game.pvzfree_row",

            // ── Browsers ─────────────────────────────────────────────────────
            "com.android.chrome",
            "org.mozilla.firefox",
            "com.opera.browser",
            "com.opera.mini.native",
            "com.microsoft.emmx",           // Edge
            "com.brave.browser",
            "com.UCMobile.intl",
            "com.duckduckgo.mobile.android"
        )
    }

    // ── Background HandlerThread — all work runs here, never on main thread ──
    private lateinit var timerThread: HandlerThread
    private lateinit var timerHandler: Handler

    // ── State ─────────────────────────────────────────────────────────────────
    @Volatile private var elapsedSeconds    = 0
    @Volatile private var timerRunning      = false  // actively counting seconds
    @Volatile private var monitorActive     = false  // screen is ON
    private var violationCounter            = 0
    private var graceActive                 = true   // ignore first stale screenOff
    private var lastForegroundApp           = ""     // track app switches

    // ── Combined monitor + timer Runnable ─────────────────────────────────────
    //
    // Runs every 1 second while monitorActive (screen ON).
    // Step 1 — detect foreground app and classify it.
    // Step 2 — start/stop timer based on classification.
    // Step 3 — increment counter and fire violation if threshold reached.
    private val monitorRunnable = object : Runnable {
        override fun run() {
            val fgApp       = getForegroundApp()
            val isBlocked   = isAppBlocked(fgApp)

            // ── App-switch handling ───────────────────────────────────────────
            if (fgApp != lastForegroundApp) {
                lastForegroundApp = fgApp
                if (isBlocked) {
                    // Switched TO a blocked app → reset and start timer
                    elapsedSeconds = 0
                    timerRunning   = true
                    refreshServiceNotification("Monitoring app: $fgApp")
                } else {
                    // Switched TO a system/non-blocked app → stop and reset
                    elapsedSeconds = 0
                    timerRunning   = false
                    refreshServiceNotification(
                        if (fgApp.isEmpty()) "Screen ON – waiting for app"
                        else "System app active – timer paused"
                    )
                }
            }

            // ── Timer count ───────────────────────────────────────────────────
            if (timerRunning) {
                elapsedSeconds++
                if (elapsedSeconds >= VIOLATION_THRESHOLD) {
                    onViolationDetected()
                    elapsedSeconds = 0      // reset, continue monitoring
                }
            }

            // ── Re-schedule while screen is ON ────────────────────────────────
            if (monitorActive) {
                timerHandler.postDelayed(this, 1_000)
            }
        }
    }

    // ── BroadcastReceiver for screen ON / OFF / UNLOCK ────────────────────────
    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_ON,
                Intent.ACTION_USER_PRESENT -> {
                    startMonitorLoop()
                    refreshServiceNotification("Screen ON – detecting app…")
                }
                Intent.ACTION_SCREEN_OFF -> {
                    if (graceActive) return
                    stopMonitorLoop()
                    refreshServiceNotification("Screen OFF – monitoring")
                }
            }
        }
    }

    // ── Foreground app detection ──────────────────────────────────────────────

    /**
     * Returns the package name of the app currently in the foreground.
     * Returns empty string if permission is not granted or detection fails.
     */
    private fun getForegroundApp(): String {
        return try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val now = System.currentTimeMillis()
            // Query last 5 seconds to reliably get the most recently used app
            val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, now - 5_000, now)
            stats?.maxByOrNull { it.lastTimeUsed }?.packageName ?: ""
        } catch (e: Exception) {
            ""  // fail-safe: treat as unknown
        }
    }

    /**
     * Returns true if the package is in the blocked (distraction) app list.
     * If usage permission is missing (empty package), defaults to TRUE so
     * monitoring still functions without permission.
     */
    private fun isAppBlocked(packageName: String): Boolean {
        if (packageName.isEmpty()) return true   // no permission → fail-safe: monitor
        return packageName in BLOCKED_APPS
    }

    // ── Monitor loop helpers ──────────────────────────────────────────────────

    /** Begin the 1-second poll loop. Called on screen ON. */
    private fun startMonitorLoop() {
        stopMonitorLoop()               // cancel any stale loop first
        lastForegroundApp = ""          // force re-evaluation on first tick
        monitorActive = true
        timerHandler.postDelayed(monitorRunnable, 1_000)
    }

    /** Stop the poll loop and reset all state. Called on screen OFF / destroy. */
    private fun stopMonitorLoop() {
        monitorActive  = false
        timerRunning   = false
        elapsedSeconds = 0
        timerHandler.removeCallbacks(monitorRunnable)
    }

    // ── Violation event ───────────────────────────────────────────────────────

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
        nm.notify(2000 + violationCounter, notification)
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        isRunning = true

        timerThread = HandlerThread("ScreenMonitorTimer").also { it.start() }
        timerHandler = Handler(timerThread.looper)

        createNotificationChannels()

        startForeground(
            NOTIFICATION_SERVICE_ID,
            buildServiceNotification("Smart Monitoring Active", "Initialising screen monitor…")
        )

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        registerReceiver(screenReceiver, filter)

        // Grace period: 3 s before trusting screen events, then start monitor loop
        Handler(timerThread.looper).postDelayed({
            graceActive = false
            startMonitorLoop()
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
        stopMonitorLoop()
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
