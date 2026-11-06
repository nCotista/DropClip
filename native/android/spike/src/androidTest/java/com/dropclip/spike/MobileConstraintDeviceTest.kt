package com.dropclip.spike

import android.app.ActivityManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.PersistableBundle
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MobileConstraintDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val device = UiDevice.getInstance(instrumentation)

    @Suppress("DEPRECATION")
    @Test fun connectedDeviceServiceStartsInForeground() {
        val activity = instrumentation.startActivitySync(
            Intent(context, SpikeHarnessActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        try {
            context.startForegroundService(Intent(context, SpikeConnectedService::class.java))
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            assertTrue(waitFor {
                manager.getRunningServices(50).any {
                    it.service.className == SpikeConnectedService::class.java.name && it.foreground
                }
            })
        } finally {
            context.stopService(Intent(context, SpikeConnectedService::class.java))
            activity.finish()
        }
    }

    @Test fun tileReadsOrdinaryClipboardFromTransientActivity() {
        assertTrue(clickTileWithClip(sensitive = false))
    }

    @Test fun tileSuppressesSensitiveClipboard() {
        assertFalse(clickTileWithClip(sensitive = true))
    }

    private fun clickTileWithClip(sensitive: Boolean): Boolean {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newPlainText("probe", "disposable test value")
        if (sensitive) clip.description.extras = PersistableBundle().apply {
            putBoolean(MobileConstraintProbe.SENSITIVE_KEY, true)
        }
        val results = context.getSharedPreferences("spike_results", Context.MODE_PRIVATE)
        results.edit().remove("clipboard_accessible").commit()
        clipboard.setPrimaryClip(clip)
        val component = "com.dropclip.spike/.SpikeTileService"
        device.executeShellCommand("cmd statusbar add-tile $component")
        try {
            device.executeShellCommand("cmd statusbar click-tile $component")
            assertTrue("Tile did not launch the transient activity", waitFor {
                results.contains("clipboard_accessible")
            })
            return results.getBoolean("clipboard_accessible", false)
        } finally {
            device.executeShellCommand("cmd statusbar remove-tile $component")
            clipboard.clearPrimaryClip()
        }
    }

    private fun waitFor(condition: () -> Boolean): Boolean {
        repeat(50) {
            if (condition()) return true
            Thread.sleep(100)
        }
        return false
    }
}
