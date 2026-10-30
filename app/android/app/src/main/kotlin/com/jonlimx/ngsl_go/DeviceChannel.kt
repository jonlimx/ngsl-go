package com.jonlimx.ngsl_go

import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Model/display capability only; no serial, account, or learner identifiers. */
class DeviceChannel(context: Context, engine: FlutterEngine) {
    // Fail closed until Dart has restored this device's display preference.
    var offline = true
        private set
    init {
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.jonlimx.ngsl_go/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deviceInfo" -> {
                        val models = mutableListOf(Build.MODEL, Build.PRODUCT, Build.DEVICE)
                        // Some ROMs publish the marketed model in a separate
                        // property. Optional reads fail safely on restricted ROMs.
                        for (key in listOf("ro.product.marketname", "ro.product.vendor.model", "ro.product.odm.model")) {
                            try {
                                val value = Class.forName("android.os.SystemProperties")
                                    .getMethod("get", String::class.java).invoke(null, key) as String
                                if (value.isNotBlank()) models.add(value)
                            } catch (_: Exception) { /* public Build fields remain available */ }
                        }
                        result.success(mapOf("brand" to Build.BRAND, "manufacturer" to Build.MANUFACTURER,
                            "models" to models.distinct(), "features" to context.packageManager.systemAvailableFeatures.mapNotNull { it.name }))
                    }
                    "setOffline" -> {
                        offline = call.arguments as? Boolean ?: true
                        if (offline) context.stopService(Intent(context, LoginKeepAliveService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
