package com.govipservices.govipservices

import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingDeepLink: String? = null

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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEEP_LINKS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialLink" -> {
                    result.success(pendingDeepLink ?: intent?.dataString)
                    pendingDeepLink = null
                }
                else -> result.notImplemented()
            }
        }

        pendingDeepLink = intent?.dataString
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val deepLink = intent.dataString ?: return
        pendingDeepLink = deepLink

        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, DEEP_LINKS_CHANNEL).invokeMethod(
                "onDeepLink",
                deepLink,
            )
            pendingDeepLink = null
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
        const val DEEP_LINKS_CHANNEL = "govipservices/deep_links"
        const val GOOGLE_MAPS_METADATA_KEY = "com.google.android.geo.API_KEY"
    }
}
