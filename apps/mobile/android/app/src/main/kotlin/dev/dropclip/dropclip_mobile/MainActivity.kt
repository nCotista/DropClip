package dev.dropclip.dropclip_mobile

import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Free space where received files go, so the app can refuse an offer
        // that would not fit instead of filling the phone.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dropclip/storage")
            .setMethodCallHandler { call, result ->
                if (call.method != "freeBytes") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    // The folder may not exist yet: ask its nearest parent.
                    var dir: File? = File(call.argument<String>("path") ?: filesDir.path)
                    while (dir != null && !dir.exists()) dir = dir.parentFile
                    result.success(StatFs((dir ?: filesDir).path).availableBytes)
                } catch (e: Exception) {
                    result.success(null)
                }
            }
    }
}
