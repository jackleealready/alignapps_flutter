package com.alignapps.flutter

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.google.android.gms.ads.identifier.AdvertisingIdClient
import com.alignapps.sdk.AlignApps
import com.alignapps.sdk.AlignAppsConfig
import com.alignapps.sdk.AlignAppsConsent
import com.alignapps.sdk.AlignAppsException
import com.alignapps.sdk.AlignAppsInitCallback
import com.alignapps.sdk.AlignAppsLogLevel
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.PluginRegistry

class AlignappsFlutterPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
    PluginRegistry.NewIntentListener {

    private var channel: MethodChannel? = null
    private var applicationContext: Context? = null
    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        applicationContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(call, result)
            "track" -> track(call, result)
            "trackPurchase" -> trackPurchase(call, result)
            "setConsent" -> setConsent(call, result)
            "getConsent" -> result.success(consentToMap(AlignApps.getConsent()))
            "setUserId" -> {
                AlignApps.setUserId(call.argument<String>("userId"))
                result.success(null)
            }
            "setInstallToken" -> {
                val token = call.argument<String>("token")
                if (token.isNullOrBlank()) {
                    result.error("invalid_arguments", "token must not be blank", null)
                } else {
                    AlignApps.setInstallToken(token)
                    result.success(null)
                }
            }
            "handleDeepLink" -> handleDeepLink(call, result)
            "flush" -> {
                AlignApps.flush()
                result.success(null)
            }
            "getInstallId" -> result.success(AlignApps.getInstallId())
            "isInitialized" -> result.success(AlignApps.isInitialized())
            "setLogLevel" -> setLogLevel(call, result)
            "requestTrackingAuthorization" -> result.success(3)
            "getAttStatus" -> result.success("not_applicable")
            "updateSkanConversionValue" -> result.success(null)
            "disableSkanAttribution" -> result.success(null)
            "getDeviceInfo" -> getDeviceInfo(result)
            else -> result.notImplemented()
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val context = applicationContext
        if (context == null) {
            result.error("not_attached", "Flutter plugin is not attached to an engine", null)
            return
        }

        val config = try {
            parseConfig(call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>())
        } catch (error: Throwable) {
            result.error("invalid_arguments", error.message ?: "Invalid configuration", null)
            return
        }

        AlignApps.initialize(context, config, object : AlignAppsInitCallback {
            override fun onSuccess(installId: String) {
                result.success(installId)
            }

            override fun onFailure(error: AlignAppsException) {
                result.error("initialize_failed", error.message, null)
            }
        })
    }

    private fun track(call: MethodCall, result: MethodChannel.Result) {
        val eventName = call.argument<String>("eventName")
        if (eventName.isNullOrBlank()) {
            result.error("invalid_arguments", "eventName must not be blank", null)
            return
        }
        AlignApps.track(eventName, readProperties(call))
        result.success(null)
    }

    private fun trackPurchase(call: MethodCall, result: MethodChannel.Result) {
        val orderId = call.argument<String>("orderId")
        val revenue = call.argument<Number>("revenue")?.toDouble()
        val currency = call.argument<String>("currency")
        if (orderId.isNullOrBlank() || revenue == null || currency.isNullOrBlank()) {
            result.error("invalid_arguments", "orderId, revenue and currency are required", null)
            return
        }
        AlignApps.trackPurchase(orderId, revenue, currency, readProperties(call))
        result.success(null)
    }

    private fun setConsent(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
        AlignApps.setConsent(
            AlignAppsConsent(
                analytics = args["analytics"] as? Boolean ?: true,
                advertisingId = args["advertisingId"] as? Boolean ?: true
            )
        )
        result.success(null)
    }

    private fun handleDeepLink(call: MethodCall, result: MethodChannel.Result) {
        val rawUrl = call.argument<String>("url")
        if (rawUrl.isNullOrBlank()) {
            result.error("invalid_arguments", "url must not be blank", null)
            return
        }
        val handled = runCatching { AlignApps.handleDeepLink(Uri.parse(rawUrl)) }.getOrDefault(false)
        result.success(handled)
    }

    private fun setLogLevel(call: MethodCall, result: MethodChannel.Result) {
        val value = call.argument<String>("level")
        val level = runCatching {
            AlignAppsLogLevel.valueOf(value?.uppercase() ?: "")
        }.getOrNull()
        if (level == null) {
            result.error("invalid_arguments", "Unknown log level", null)
        } else {
            AlignApps.setLogLevel(level)
            result.success(null)
        }
    }

    private fun getDeviceInfo(result: MethodChannel.Result) {
        val context = applicationContext
        if (context == null) {
            result.error("not_attached", "Flutter plugin is not attached to an engine", null)
            return
        }
        Thread {
            val info = mutableMapOf<String, Any?>(
                "platform" to "android",
                "install_id" to AlignApps.getInstallId()
            )
            try {
                val advertising = AdvertisingIdClient.getAdvertisingIdInfo(context)
                info["advertising_id"] = advertising.id
                info["lat"] = advertising.isLimitAdTrackingEnabled
            } catch (_: Throwable) {
                info["advertising_id"] = null
                info["lat"] = null
            }
            Handler(Looper.getMainLooper()).post { result.success(info) }
        }.start()
    }

    private fun parseConfig(args: Map<*, *>): AlignAppsConfig {
        val appKey = args["appKey"] as? String ?: ""
        val serverUrl = args["serverUrl"] as? String ?: ""
        val consentMap = args["initialConsent"] as? Map<*, *> ?: emptyMap<Any?, Any?>()
        val logLevel = runCatching {
            AlignAppsLogLevel.valueOf(
                (args["logLevel"] as? String)?.uppercase() ?: AlignAppsLogLevel.WARN.name
            )
        }.getOrDefault(AlignAppsLogLevel.WARN)

        return AlignAppsConfig(
            appKey = appKey,
            serverUrl = serverUrl,
            logLevel = logLevel,
            enableInstallReferrer = args["enableInstallReferrer"] as? Boolean ?: true,
            autoTrackSessions = args["autoTrackSessions"] as? Boolean ?: true,
            sessionTimeoutSeconds = (args["sessionTimeoutSeconds"] as? Number)?.toLong() ?: 1_800,
            flushIntervalSeconds = (args["flushIntervalSeconds"] as? Number)?.toLong() ?: 15,
            maxQueueSize = (args["maxQueueSize"] as? Number)?.toInt() ?: 500,
            requestTimeoutSeconds = (args["requestTimeoutSeconds"] as? Number)?.toLong() ?: 15,
            debug = args["debug"] as? Boolean ?: false,
            initialConsent = AlignAppsConsent(
                analytics = consentMap["analytics"] as? Boolean ?: true,
                advertisingId = consentMap["advertisingId"] as? Boolean ?: true
            ),
            installToken = args["installToken"] as? String
        )
    }

    private fun readProperties(call: MethodCall): Map<String, Any?> {
        val raw = call.argument<Map<*, *>>("properties") ?: return emptyMap()
        return raw.entries.associate { (key, value) -> key.toString() to value }
    }

    private fun consentToMap(consent: AlignAppsConsent): Map<String, Any> {
        return mapOf(
            "analytics" to consent.analytics,
            "advertisingId" to consent.advertisingId
        )
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        AlignApps.handleIntent(binding.activity.intent)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    override fun onNewIntent(intent: Intent): Boolean {
        return AlignApps.handleIntent(intent)
    }

    private fun detachActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    private companion object {
        const val CHANNEL_NAME = "com.alignapps/flutter"
    }
}
