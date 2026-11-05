package com.dropclip.spike

import android.os.Bundle
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Android instrumentation tests for the decision points. */
class MobileConstraintProbeTest {
    @Test fun android14UsesPendingIntent() {
        assertTrue(MobileConstraintProbe.needsPendingIntent(34))
        assertTrue(MobileConstraintProbe.needsPendingIntent(35))
    }

    @Test fun android13KeepsLegacyTilePath() {
        assertFalse(MobileConstraintProbe.needsPendingIntent(33))
    }

    @Test fun sensitiveClipIsBlocked() {
        assertTrue(MobileConstraintProbe.isSensitive(Bundle().apply {
            putBoolean(MobileConstraintProbe.SENSITIVE_KEY, true)
        }))
    }

    @Test fun ordinaryAndMissingMetadataAreNotSensitive() {
        assertFalse(MobileConstraintProbe.isSensitive(Bundle()))
        assertFalse(MobileConstraintProbe.isSensitive(null))
    }
}
