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
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.SystemClock
import android.telephony.SmsManager
import androidx.core.app.NotificationCompat

class MonitoringService : Service() {

    companion object {
        const val NOTIFICATION_SERVICE_ID   = 1001
        const val CHANNEL_SERVICE           = "smart_monitor_service"
        const val CHANNEL_VIOLATION         = "smart_monitor_violation"
        const val VIOLATION_THRESHOLD       = 20
        const val ACTIVE_CHECK_INTERVAL_MS  = 1_000L
        const val PASSIVE_CHECK_INTERVAL_MS = 10_000L

        @Volatile var isRunning              = false
        @Volatile var monitoringActive       = false
        @Volatile var adminMonitoringEnabled = true
        @Volatile var lastTimetablePushMs    = 0L
        @Volatile var dartDebugInfo          = ""
        @Volatile var currentPeriod          = ""
        @Volatile var flutterChannel: io.flutter.plugin.common.MethodChannel? = null

        // Admin phone number — pushed from Flutter via "setAdminPhone" MethodChannel
        @Volatile var adminPhoneNumber = ""
        @Volatile var studentNameForAlerts = "Student"
        @Volatile var studentRegNoForAlerts = ""

        val BLOCKED_APPS: Set<String> = setOf(
            "com.instagram.android", "com.facebook.katana", "com.facebook.lite",
            "com.twitter.android", "com.twitter.android.lite",
            "com.snapchat.android", "com.whatsapp", "com.whatsapp.w4b",
            "org.telegram.messenger", "com.zhiliaoapp.musically",
            "com.ss.android.ugc.trill", "com.pinterest", "com.reddit.frontpage",
            "com.linkedin.android", "com.tumblr", "com.discord",
            "com.sharechat.app", "com.imo.android.imoim",
            "com.google.android.youtube", "com.netflix.mediaclient",
            "com.amazon.avod.thirdpartyclient", "in.startv.hotstar",
            "com.disney.disneyplus", "tv.twitch.android.app",
            "com.facebook.orca", "com.vanced.android.youtube",
            "app.revanced.android.youtube", "com.zee5", "com.voot.app",
            "com.jio.jioplay.tv", "com.mxtech.videoplayer.ad",
            "com.supercell.clashofclans", "com.supercell.clashroyale",
            "com.supercell.brawlstars", "com.king.candycrushsaga",
            "com.activision.callofduty.shooter", "com.garena.game.freefire",
            "com.pubg.imobile", "com.tencent.ig", "com.kiloo.subwaysurf",
            "com.outfit7.talkingtom2", "com.mojang.minecraftpe",
            "com.roblox.client", "com.ea.game.pvzfree_row",
            "com.garena.game.codm", "com.imangi.templerun2",
            "com.miniclip.eightballpool",
            "com.android.chrome", "org.mozilla.firefox",
            "com.opera.browser", "com.opera.mini.native",
            "com.microsoft.emmx", "com.brave.browser",
            "com.UCMobile.intl", "com.duckduckgo.mobile.android",
            "com.kiwibrowser.browser", "com.uc.browser.en"
        )

        val BLOCKED_APP_PREFIXES: Set<String> = setOf(
            "com.instagram", "com.facebook", "com.twitter", "com.x.",
            "com.snapchat", "com.whatsapp", "org.telegram", "com.zhiliaoapp",
            "com.ss.android.ugc", "com.reddit", "com.discord",
            "com.google.android.youtube", "com.netflix", "com.amazon.avod",
            "in.startv.hotstar", "com.disney", "tv.twitch", "com.zee5",
            "com.voot", "com.jio", "com.mxtech", "com.supercell", "com.king.",
            "com.activision", "com.garena", "com.pubg", "com.tencent.ig",
            "com.roblox", "com.mojang", "com.miniclip", "com.android.chrome",
            "org.mozilla", "com.opera", "com.microsoft.emmx", "com.brave",
            "com.UCMobile", "com.uc."
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
    private var currentMode       = "sleep"

    // Internet state tracking
    @Volatile private var lastInternetState = false

    // ✅ FIXED: Store NetworkCallback reference so we can unregister in onDestroy
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    private fun resetSession() {
        elapsedSeconds  = 0
        lastDetectedApp = "__init__"
        timerRunning    = false
    }

    // ── SmsManager helper (handles API 31+ and older) ─────────────────────────
    private fun getSmsManager(): SmsManager =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            getSystemService(SmsManager::class.java)
        else
            @Suppress("DEPRECATION") SmsManager.getDefault()

    // ── SMS: Violation alert (internet OFF or ON — SIM la direct) ─────────────
    private fun sendSmsToAdmin(secondsUsed: Int, period: String) {
        val phone = adminPhoneNumber.trim()
        if (phone.isEmpty()) {
            android.util.Log.w("MonitoringService", "SMS skipped — adminPhoneNumber not set")
            return
        }
        try {
            val label = if (studentRegNoForAlerts.isNotBlank()) {
                "$studentNameForAlerts (${studentRegNoForAlerts.trim()})"
            } else {
                studentNameForAlerts
            }
            val timeStr = java.text.SimpleDateFormat("hh:mm a", java.util.Locale.getDefault())
                .format(java.util.Date())
            val message =
                "SMART CLASSROOM ALERT\n" +
                "Student: $label\n" +
                "Phone usage detected during class!\n" +
                "Period: $period\n" +
                "Duration: ${secondsUsed}s\n" +
                "Time: $timeStr"

            val sms = getSmsManager()
            val parts = sms.divideMessage(message)
            sms.sendMultipartTextMessage(phone, null, parts, null, null)
            android.util.Log.d("MonitoringService", "✅ Violation SMS sent to: $phone")
        } catch (e: Exception) {
            android.util.Log.e("MonitoringService", "❌ Violation SMS failed: ${e.message}")
        }
    }

    // ── SMS: Internet OFF alert ───────────────────────────────────────────────
    private fun sendInternetOffAlert() {
        val phone = adminPhoneNumber.trim()
        if (phone.isEmpty()) {
            android.util.Log.w("MonitoringService", "Internet-off SMS skipped — adminPhoneNumber not set")
            return
        }
        try {
            val label = if (studentRegNoForAlerts.isNotBlank()) {
                "$studentNameForAlerts (${studentRegNoForAlerts.trim()})"
            } else {
                studentNameForAlerts
            }
            val timeStr = java.text.SimpleDateFormat("hh:mm a", java.util.Locale.getDefault())
                .format(java.util.Date())
            val message =
                "SMART CLASSROOM ALERT\n" +
                "Student: $label\n" +
                "Internet connection turned OFF!\n" +
                "Period: $currentPeriod\n" +
                "Time: $timeStr"

            val sms = getSmsManager()
            val parts = sms.divideMessage(message)
            sms.sendMultipartTextMessage(phone, null, parts, null, null)
            android.util.Log.d("MonitoringService", "✅ Internet-OFF SMS sent to: $phone")
        } catch (e: Exception) {
            android.util.Log.e("MonitoringService", "❌ Internet-OFF SMS failed: ${e.message}")
        }
    }

    // ── Internet connectivity monitor ─────────────────────────────────────────
    private fun setupConnectivityMonitoring() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        lastInternetState = cm.activeNetwork?.let { network ->
            val caps = cm.getNetworkCapabilities(network)
            caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        } ?: false

        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        // ✅ FIXED: Named callback stored so onDestroy can unregister it
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                lastInternetState = true
                android.util.Log.d("MonitoringService", "🌐 Internet available")
            }

            override fun onLost(network: Network) {
                // Only alert when internet goes OFF during active class monitoring
                if (lastInternetState && monitoringActive && adminMonitoringEnabled) {
                    android.util.Log.w("MonitoringService", "⚠️ Internet LOST during class!")
                    sendInternetOffAlert()
                }
                lastInternetState = false
            }
        }

        cm.registerNetworkCallback(request, callback)
        networkCallback = callback // ✅ Save reference for cleanup
    }

    // ── 1-second tick loop ────────────────────────────────────────────────────
    private val tickRunnable = object : Runnable {
        override fun run() {
            val timetableOn       = monitoringActive
            val monitoringAllowed = timetableOn && adminMonitoringEnabled

            if (!isScreenOn) {
                currentMode = "sleep"
                resetSession()
                refreshServiceNotification("Smart Classroom", "Screen OFF - monitoring sleep mode")
                sendLiveUpdateToFlutter("", 0, timetableOn, currentMode)
                timerHandler.postDelayed(this, PASSIVE_CHECK_INTERVAL_MS)
                return
            }

            val currentApp     = getCurrentForegroundApp()
            val interactiveApp = isBlockedApp(currentApp)
            val systemApp      = isSystemApp(currentApp)
            val nextMode       = if (monitoringAllowed && interactiveApp) "active" else "passive"
            val appChanged     = currentApp != lastDetectedApp

            if (nextMode != currentMode) {
                currentMode = nextMode
                if (currentMode != "active") resetSession()
            }

            if (currentMode == "active") {
                if (appChanged) {
                    lastDetectedApp = currentApp
                    elapsedSeconds  = 0
                }
                timerRunning = true
                elapsedSeconds++

                refreshServiceNotification(
                    "\uD83D\uDD35 Class Time — Active Monitoring",
                    "${elapsedSeconds}s / ${VIOLATION_THRESHOLD}s on ${friendlyAppName(currentApp)}"
                )

                if (elapsedSeconds > VIOLATION_THRESHOLD) {
                    fireViolationNotification(elapsedSeconds)
                    elapsedSeconds = 0
                }

                sendLiveUpdateToFlutter(currentApp, elapsedSeconds, timetableOn, currentMode)
                timerHandler.postDelayed(this, ACTIVE_CHECK_INTERVAL_MS)
                return
            }

            // Passive mode
            timerRunning    = false
            elapsedSeconds  = 0
            lastDetectedApp = currentApp

            val passiveText = when {
                !monitoringAllowed       -> "Monitoring paused (break/admin)"
                systemApp               -> "System app: ${friendlyAppName(currentApp)}"
                currentApp.isNotEmpty() -> "Passive: ${friendlyAppName(currentApp)}"
                else                    -> "Passive mode"
            }

            refreshServiceNotification("\uD83D\uDFE1 Passive Monitoring", passiveText)
            sendLiveUpdateToFlutter(currentApp, 0, timetableOn, currentMode)
            timerHandler.postDelayed(this, PASSIVE_CHECK_INTERVAL_MS)
        }
    }

    // ── Screen ON/OFF receiver ────────────────────────────────────────────────
    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_ON,
                Intent.ACTION_USER_PRESENT -> {
                    isScreenOn = true
                    resetSession()
                    refreshServiceNotification("Smart Classroom", "Screen ON - detecting app...")
                }
                Intent.ACTION_SCREEN_OFF -> {
                    if (graceActive) return
                    isScreenOn  = false
                    currentMode = "sleep"
                    resetSession()
                    refreshServiceNotification("Smart Classroom", "Screen OFF - monitoring paused")
                }
            }
        }
    }

    // ── Foreground app detection ──────────────────────────────────────────────
    private fun getCurrentForegroundApp(): String {
        return try {
            val usm    = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val now    = System.currentTimeMillis()
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
        if (pkg.isEmpty()) return false
        if (pkg in BLOCKED_APPS) return true
        return BLOCKED_APP_PREFIXES.any { pkg.startsWith(it) }
    }

    private fun isSystemApp(pkg: String): Boolean {
        if (pkg.isEmpty()) return false
        if (pkg == "android" || pkg == "com.android.systemui" ||
            pkg.startsWith("com.android.")) return true
        return try {
            val info = packageManager.getApplicationInfo(pkg, 0)
            (info.flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
            (info.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
        } catch (_: Exception) { false }
    }

    private fun friendlyAppName(pkg: String): String {
        if (pkg.isBlank()) return "Unknown"
        return when (pkg) {
            "com.whatsapp"               -> "WhatsApp"
            "com.instagram.android"      -> "Instagram"
            "com.android.chrome"         -> "Chrome"
            "com.google.android.youtube" -> "YouTube"
            "com.android.settings"       -> "Settings"
            "com.android.systemui"       -> "System UI"
            else -> pkg.substringAfterLast('.')
        }
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    override fun onCreate() {
        super.onCreate()
        isRunning = true

        timerThread  = HandlerThread("SCMonitorThread").also { it.start() }
        timerHandler = Handler(timerThread.looper)

        // Start internet OFF detection (SMS alert when student disables internet)
        setupConnectivityMonitoring()

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

        // ✅ FIXED: Properly unregister NetworkCallback — prevents memory leak
        try {
            networkCallback?.let {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                cm.unregisterNetworkCallback(it)
            }
        } catch (_: Exception) {}
        networkCallback = null
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Violation fired ───────────────────────────────────────────────────────
    private fun fireViolationNotification(secondsUsed: Int) {
        violationCounter++

        // Step 1: Local notification on student phone (always works)
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

        // Step 2: Flutter callback → Firestore + FCM (internet ON)
        flutterChannel?.let { ch ->
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                ch.invokeMethod("onViolation", mapOf(
                    "secondsUsed" to secondsUsed,
                    "period"      to currentPeriod
                ))
            }
        } ?: android.util.Log.w("MonitoringService", "flutterChannel null — FCM skipped")

        // Step 3: SMS via SIM — works even when internet is COMPLETELY OFF
        sendSmsToAdmin(secondsUsed, currentPeriod)
    }

    // ── Live update to Flutter ────────────────────────────────────────────────
    private fun sendLiveUpdateToFlutter(
        currentApp: String, screenTime: Int, monitoringOn: Boolean, mode: String
    ) {
        val channel = flutterChannel ?: return
        val status  = when {
            !isScreenOn      -> "idle"
            mode == "active" -> "active"
            else             -> "idle"
        }
        val args = mapOf(
            "currentApp"   to (if (currentApp.isBlank()) "" else currentApp),
            "screenTime"   to screenTime,
            "period"       to currentPeriod,
            "monitoringOn" to monitoringOn,
            "status"       to status,
            "mode"         to mode
        )
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            channel.invokeMethod("onLiveUpdate", args)
        }
    }

    // ── Notification helpers ──────────────────────────────────────────────────
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
        nm.notify(NOTIFICATION_SERVICE_ID, buildServiceNotification(title, text))
    }
}
