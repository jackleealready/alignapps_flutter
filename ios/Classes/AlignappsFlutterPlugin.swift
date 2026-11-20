import Flutter
import UIKit

public final class AlignappsFlutterPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    private var core: AlignappsCore?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.alignapps/flutter",
            binaryMessenger: registrar.messenger()
        )
        let instance = AlignappsFlutterPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            initialize(call, result: result)
        case "track":
            guard let core else { return result(fluttered("not_initialized", "AlignApps is not initialized")) }
            guard let args = call.arguments as? [String: Any],
                  let eventName = args["eventName"] as? String,
                  !eventName.isEmpty else {
                return result(fluttered("invalid_arguments", "eventName must not be blank"))
            }
            core.track(eventName, properties: args["properties"] as? [String: Any] ?? [:])
            result(nil)
        case "trackPurchase":
            guard let core else { return result(fluttered("not_initialized", "AlignApps is not initialized")) }
            guard let args = call.arguments as? [String: Any],
                  let orderId = args["orderId"] as? String,
                  let revenue = (args["revenue"] as? NSNumber)?.doubleValue,
                  let currency = args["currency"] as? String else {
                return result(fluttered("invalid_arguments", "orderId, revenue and currency are required"))
            }
            core.trackPurchase(
                orderId,
                revenue: revenue,
                currency: currency,
                properties: args["properties"] as? [String: Any] ?? [:]
            )
            result(nil)
        case "setConsent":
            guard let core else { return result(fluttered("not_initialized", "AlignApps is not initialized")) }
            core.setConsent(AlignappsConsent.from(call.arguments as? [String: Any]))
            result(nil)
        case "getConsent":
            guard let core else { return result(fluttered("not_initialized", "AlignApps is not initialized")) }
            result(core.getConsent().toMap())
        case "setUserId":
            guard let core else { return result(fluttered("not_initialized", "AlignApps is not initialized")) }
            core.setUserId((call.arguments as? [String: Any])?["userId"] as? String)
            result(nil)
        case "setInstallToken":
            guard let core else { return result(fluttered("not_initialized", "AlignApps is not initialized")) }
            guard let token = (call.arguments as? [String: Any])?["token"] as? String, !token.isEmpty else {
                return result(fluttered("invalid_arguments", "token must not be blank"))
            }
            core.setInstallToken(token)
            result(nil)
        case "handleDeepLink":
            guard let core else { return result(fluttered("not_initialized", "AlignApps is not initialized")) }
            guard let url = (call.arguments as? [String: Any])?["url"] as? String, !url.isEmpty else {
                return result(fluttered("invalid_arguments", "url must not be blank"))
            }
            result(core.handleDeepLink(url))
        case "flush":
            guard let core else { return result(fluttered("not_initialized", "AlignApps is not initialized")) }
            core.flush()
            result(nil)
        case "getInstallId":
            result(core?.installId)
        case "isInitialized":
            result(core?.isInitialized ?? false)
        case "setLogLevel":
            guard let core else { return result(fluttered("not_initialized", "AlignApps is not initialized")) }
            guard let level = (call.arguments as? [String: Any])?["level"] as? String else {
                return result(fluttered("invalid_arguments", "Unknown log level"))
            }
            core.setLogLevel(level)
            result(nil)
        case "requestTrackingAuthorization":
            guard let core else { return result(fluttered("not_initialized", "AlignApps is not initialized")) }
            core.requestTrackingAuthorization { status in
                DispatchQueue.main.async { result(status) }
            }
        case "getAttStatus":
            result(core?.getAttStatus() ?? AlignappsDevice.attStatus())
        case "getDeviceInfo":
            result(core?.deviceInfo() ?? ["platform": "ios"])
        case "updateSkanConversionValue":
            guard let core else { return result(fluttered("not_initialized", "AlignApps is not initialized")) }
            let args = call.arguments as? [String: Any]
            let value = (args?["conversionValue"] as? NSNumber)?.intValue ?? 0
            let coarse = args?["coarseValue"] as? String ?? "low"
            let lockWindow = args?["lockWindow"] as? Bool ?? false
            core.updateSkanConversionValue(value: value, coarse: coarse, lockWindow: lockWindow)
            result(nil)
        case "disableSkanAttribution":
            core?.disableSkanAttribution()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func initialize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let config = AlignappsConfig.from(args) else {
            result(fluttered("invalid_arguments", "Invalid configuration"))
            return
        }
        let core = AlignappsCore(config: config)
        core.onSkanUpdated = { [weak self] data in
            DispatchQueue.main.async {
                self?.channel?.invokeMethod("skanUpdated", arguments: data)
            }
        }
        self.core = core
        let installId = core.start()
        result(installId)
    }

    private func fluttered(_ code: String, _ message: String) -> FlutterError {
        FlutterError(code: code, message: message, details: nil)
    }
}
