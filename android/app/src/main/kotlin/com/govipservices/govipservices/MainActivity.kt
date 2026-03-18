package com.govipservices.govipservices

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getGoogleMapsApiKey" -> result.success(readGoogleMapsApiKey())
                else -> result.notImplemented()
            }
        }
    }

    private fun readGoogleMapsApiKey(): String? {
        return try {
            val applicationInfo = packageManager.getApplicationInfo(
                packageName,
                PackageManager.GET_META_DATA,
            )
            applicationInfo.metaData
                ?.getString(GOOGLE_MAPS_METADATA_KEY)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
        } catch (_: Exception) {
            null
        }
    }

    private companion object {
        const val CHANNEL = "govipservices/runtime_config"
        const val GOOGLE_MAPS_METADATA_KEY = "com.google.android.geo.API_KEY"
    }
}
