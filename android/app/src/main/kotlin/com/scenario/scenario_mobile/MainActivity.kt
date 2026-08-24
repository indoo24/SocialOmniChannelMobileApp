package com.scenario.scenario_mobile

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter engine, and owns the one thing Flutter cannot set itself:
 * the window's FLAG_SECURE.
 *
 * FLAG_SECURE tells the framework that this window's contents must not be
 * captured. With it set, the screenshot shortcut fails, screen recording
 * captures black, and — the case that matters most here — the snapshot Android
 * stores to render the task switcher is blank rather than a picture of an open
 * customer conversation.
 *
 * The flag is toggled per screen from Dart rather than set once here, because
 * it also blocks legitimate screen sharing; see core/security/screen_security.dart
 * for that reasoning. The window flag must be changed on the UI thread, which
 * is where MethodChannel handlers already run.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.scenario.scenario_mobile/screen_security"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val secure = call.argument<Boolean>("secure") ?: false
                        if (secure) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
