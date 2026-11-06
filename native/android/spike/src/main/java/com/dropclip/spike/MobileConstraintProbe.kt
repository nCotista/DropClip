package com.dropclip.spike

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PersistableBundle
import android.service.quicksettings.TileService
import android.widget.Toast

/** ADR-007 probe. Register these classes in a disposable Android test app. */
object MobileConstraintProbe {
    const val SENSITIVE_KEY = "android.content.extra.IS_SENSITIVE"

    fun needsPendingIntent(api: Int): Boolean = api >= 34

    fun isSensitive(extras: PersistableBundle?): Boolean =
        extras?.getBoolean(SENSITIVE_KEY, false) == true

    fun clipboardIntent(context: Context): Intent = Intent(context, SpikeClipboardActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
}

class SpikeTileService : TileService() {
    override fun onClick() {
        super.onClick()
        val intent = MobileConstraintProbe.clipboardIntent(this)
        if (MobileConstraintProbe.needsPendingIntent(Build.VERSION.SDK_INT)) {
            val pending = PendingIntent.getActivity(
                this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}

/** Visible entry point for starting the service during instrumentation. */
class SpikeHarnessActivity : Activity()

/** Read only after foreground focus; never log the clipboard value. */
class SpikeClipboardActivity : Activity() {
    private var sampled = false

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || sampled) return
        sampled = true
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val concealed = MobileConstraintProbe.isSensitive(clipboard.primaryClipDescription?.extras)
        val present = !concealed && (clipboard.primaryClip?.itemCount ?: 0) > 0
        getSharedPreferences("spike_results", MODE_PRIVATE).edit()
            .putBoolean("clipboard_accessible", present).commit()
        Toast.makeText(this, if (present) "Clipboard accessible" else "Clipboard blocked or empty", Toast.LENGTH_SHORT).show()
        setResult(if (present) RESULT_OK else RESULT_CANCELED)
        finish()
    }
}

/** Separate service checks connectedDevice type and multicast lock lifecycle. */
class SpikeConnectedService : Service() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel(
            "dropclip_spike", "DropClip spike", NotificationManager.IMPORTANCE_LOW
        ))
        val notification = Notification.Builder(this, "dropclip_spike")
            .setContentTitle("DropClip spike")
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(53317, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(53317, notification)
        }
    }

    fun beginDiscovery(): Boolean {
        val wifi = getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return false
        val lock = multicastLock ?: wifi.createMulticastLock("dropclip_spike_mdns").also {
            it.setReferenceCounted(false)
            multicastLock = it
        }
        if (!lock.isHeld) lock.acquire()
        return lock.isHeld
    }

    fun endDiscovery() {
        multicastLock?.let { if (it.isHeld) it.release() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        getSharedPreferences("spike_results", MODE_PRIVATE).edit()
            .putBoolean("multicast_lock_held", beginDiscovery()).commit()
        return START_STICKY
    }
    override fun onDestroy() {
        endDiscovery()
        super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
}
