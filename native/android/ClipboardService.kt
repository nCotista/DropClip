package com.dropclip.nativebridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.provider.Settings

/**
 * Android Foreground Service managing passive clipboard writes, mDNS MulticastLock,
 * Doze battery exemption, and WebSocket lifecycle (FR-03B, NFR-R03A, ADR-007, PROTO §14.2).
 */
class DropClipForegroundService : Service() {

    private val CHANNEL_ID = "dropclip_persistent_channel"
    private val NOTIFICATION_ID = 53317
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        val notification = buildForegroundNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onDestroy() {
        releaseMulticastLock()
        super.onDestroy()
    }

    /** Acquires WifiManager.MulticastLock so UDP 5353 mDNS packets are not dropped (PROTO §14.2). */
    fun acquireMulticastLock(): Boolean {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return false
        val lock = multicastLock ?: wifi.createMulticastLock("dropclip_mdns_lock").apply {
            setReferenceCounted(false)
            multicastLock = this
        }
        if (!lock.isHeld) {
            lock.acquire()
        }
        return lock.isHeld
    }

    /** Releases WifiManager.MulticastLock when discovery finishes or service stops. */
    fun releaseMulticastLock() {
        multicastLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
    }

    /** Checks if the app is exempted from Doze battery optimizations (NFR-R03A). */
    fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pm.isIgnoringBatteryOptimizations(packageName)
        } else {
            true
        }
    }

    /** Builds the intent for `dropclip/android/service -> requestBatteryExemption`. */
    fun buildBatteryExemptionIntent(): Intent {
        return Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:$packageName")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    /** Returns true if ClipDescription marks the clip as sensitive (NFR-S04, PROTO §10.4). */
    fun isPrimaryClipSensitive(): Boolean {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val desc = clipboard.primaryClipDescription ?: return false
        return desc.extras?.getBoolean("android.content.extra.IS_SENSITIVE", false) == true ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                desc.extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE, false) == true)
    }

    /** Writes incoming clipboard data from desktop directly to Android primary clip (Passive Inbound). */
    fun setPrimaryClip(text: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newPlainText("DropClip", text)
        clipboard.setPrimaryClip(clip)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "DropClip Continuity Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps DropClip connected in local network"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("DropClip Connected")
            .setContentText("Monitoring local network clipboard events")
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setOngoing(true)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

/** Auto-starts DropClipForegroundService on device reboot (T2.1 AC #4). */
class DropClipBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            val serviceIntent = Intent(context, DropClipForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        }
    }
}
