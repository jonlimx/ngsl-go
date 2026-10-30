package com.jonlimx.ngsl_go

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var speech: SpeechChannel? = null
    private var device: DeviceChannel? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        speech = SpeechChannel(this, engine)
        device = DeviceChannel(this, engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.jonlimx.ngsl_go/auth").setMethodCallHandler { call, result ->
            when (call.method) {
                "startLogin" -> {
                    if (device?.offline != false) result.error("OFFLINE", "墨水屏模式完全离线。", null)
                    else { startForegroundService(Intent(this, LoginKeepAliveService::class.java)); result.success(null) }
                }
                "stopLogin" -> { stopService(Intent(this, LoginKeepAliveService::class.java)); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    override fun onStop() { speech?.interrupt(); super.onStop() }
    override fun onResume() { super.onResume(); speech?.onResume() }
    override fun onDestroy() { speech?.dispose(); super.onDestroy() }
}
