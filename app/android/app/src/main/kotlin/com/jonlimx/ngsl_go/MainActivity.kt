package com.jonlimx.ngsl_go

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var speech: SpeechChannel? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        speech = SpeechChannel(this, engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.jonlimx.ngsl_go/auth").setMethodCallHandler { call, result ->
            when (call.method) {
                "startLogin" -> { startForegroundService(Intent(this, LoginKeepAliveService::class.java)); result.success(null) }
                "stopLogin" -> { stopService(Intent(this, LoginKeepAliveService::class.java)); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    override fun onStop() { speech?.stop(); super.onStop() }
    override fun onDestroy() { speech?.dispose(); super.onDestroy() }
}
