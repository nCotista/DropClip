package com.dropclip.spike

import android.app.ActivityManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.PersistableBundle
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertNotNull
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
            val results = context.getSharedPreferences("spike_results", Context.MODE_PRIVATE)
            results.edit().remove("multicast_lock_held").commit()
            context.startForegroundService(Intent(context, SpikeConnectedService::class.java))
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            assertTrue(waitFor {
                manager.getRunningServices(50).any {
                    it.service.className == SpikeConnectedService::class.java.name && it.foreground
                }
            })
            assertTrue("MulticastLock was not acquired", waitFor {
                results.getBoolean("multicast_lock_held", false)
            })
        } finally {
            context.stopService(Intent(context, SpikeConnectedService::class.java))
            activity.finish()
        }
    }

    @Test fun tileReadsOrdinaryAndSuppressesSensitiveClipboard() {
        val component = "com.dropclip.spike/.SpikeTileService"
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        device.executeShellCommand("cmd statusbar add-tile $component")
        try {
            assertTrue(clickTileWithClip(clipboard, sensitive = false))
            assertFalse(clickTileWithClip(clipboard, sensitive = true))
        } finally {
            device.executeShellCommand("cmd statusbar remove-tile $component")
            device.pressHome()
            clipboard.clearPrimaryClip()
        }
    }

    private fun clickTileWithClip(clipboard: ClipboardManager, sensitive: Boolean): Boolean {
        val clip = ClipData.newPlainText("probe", "disposable test value")
        if (sensitive) clip.description.extras = PersistableBundle().apply {
            putBoolean(MobileConstraintProbe.SENSITIVE_KEY, true)
        }
        val results = context.getSharedPreferences("spike_results", Context.MODE_PRIVATE)
        results.edit().remove("clipboard_accessible").commit()
        clipboard.setPrimaryClip(clip)
        device.pressHome()
        device.openQuickSettings()
        var tile = device.wait(Until.findObject(By.text("DropClip Probe")), 2_000)
        repeat(4) {
            if (tile == null) {
                device.swipe(
                    device.displayWidth * 3 / 4, device.displayHeight / 2,
                    device.displayWidth / 4, device.displayHeight / 2, 10
                )
                tile = device.wait(Until.findObject(By.text("DropClip Probe")), 2_000)
            }
        }
        assertNotNull("DropClip tile is missing from Quick Settings", tile)
        tile!!.click()
        assertTrue("Tile did not launch the transient activity", waitFor {
            results.contains("clipboard_accessible")
        })
        return results.getBoolean("clipboard_accessible", false)
    }

    private fun waitFor(condition: () -> Boolean): Boolean {
        repeat(50) {
            if (condition()) return true
            Thread.sleep(100)
        }
        return false
    }
}
