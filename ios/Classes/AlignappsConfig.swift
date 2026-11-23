import Foundation

struct AlignappsConsent {
    var analytics: Bool = false
    var advertisingId: Bool = false
    var adUserData: Bool? = nil
    var adPersonalization: Bool? = nil
    var eea: Bool? = nil

    static func from(_ value: [String: Any]?) -> AlignappsConsent {
        let map = value ?? [:]
        return AlignappsConsent(
            analytics: map["analytics"] as? Bool ?? false,
            advertisingId: map["advertisingId"] as? Bool ?? false,
            adUserData: map["adUserData"] as? Bool,
            adPersonalization: map["adPersonalization"] as? Bool,
            eea: map["eea"] as? Bool
        )
    }

    func toMap() -> [String: Any] {
        var map: [String: Any] = ["analytics": analytics, "advertisingId": advertisingId]
        if let adUserData { map["adUserData"] = adUserData }
        if let adPersonalization { map["adPersonalization"] = adPersonalization }
        if let eea { map["eea"] = eea }
        return map
    }

    func toAdConsentMap() -> [String: Any] {
        // ATT is tracked separately. These values come from business consent only.
        var map: [String: Any] = [
            "ad_user_data": adUserData ?? (analytics && advertisingId),
            "ad_personalization": adPersonalization ?? advertisingId
        ]
        if let eea { map["eea"] = eea }
        return map
    }
}

struct AlignappsConfig {
    let appKey: String
    let serverUrl: String
    var logLevel: String = "WARN"
    var enableInstallReferrer: Bool = true
    var autoTrackSessions: Bool = true
    var sessionTimeoutSeconds: TimeInterval = 1_800
    var flushIntervalSeconds: TimeInterval = 15
    var maxQueueSize: Int = 500
    var requestTimeoutSeconds: TimeInterval = 15
    var debug: Bool = false
    var initialConsent = AlignappsConsent()
    var installToken: String?
    var enableSkan: Bool = true
    var enableOdm: Bool = true
    var skanConversionValues: [String: Int] = [
        "install": 1,
        "register": 2,
        "purchase": 3
    ]

    static func from(_ args: [String: Any]) -> AlignappsConfig? {
        guard let appKey = (args["appKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !appKey.isEmpty,
              let serverUrl = (args["serverUrl"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !serverUrl.isEmpty,
              let url = URL(string: serverUrl),
              url.host != nil else {
            return nil
        }
        var config = AlignappsConfig(appKey: appKey, serverUrl: serverUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        config.logLevel = (args["logLevel"] as? String)?.uppercased() ?? "WARN"
        config.enableInstallReferrer = args["enableInstallReferrer"] as? Bool ?? true
        config.autoTrackSessions = args["autoTrackSessions"] as? Bool ?? true
        config.sessionTimeoutSeconds = (args["sessionTimeoutSeconds"] as? NSNumber)?.doubleValue ?? 1_800
        config.flushIntervalSeconds = (args["flushIntervalSeconds"] as? NSNumber)?.doubleValue ?? 15
        config.maxQueueSize = (args["maxQueueSize"] as? NSNumber)?.intValue ?? 500
        config.requestTimeoutSeconds = (args["requestTimeoutSeconds"] as? NSNumber)?.doubleValue ?? 15
        config.debug = args["debug"] as? Bool ?? false
        config.initialConsent = AlignappsConsent.from(args["initialConsent"] as? [String: Any])
        config.installToken = args["installToken"] as? String
        config.enableSkan = args["enableSkan"] as? Bool ?? true
        config.enableOdm = args["enableOdm"] as? Bool ?? true
        if let values = args["skanConversionValues"] as? [String: Any] {
            var parsed: [String: Int] = config.skanConversionValues
            for (key, value) in values {
                if let number = value as? NSNumber {
                    parsed[key] = number.intValue
                }
            }
            config.skanConversionValues = parsed
        }
        return config
    }
}

final class AlignappsLogger {
    private var level: String

    init(level: String) {
        self.level = level
    }

    func setLevel(_ level: String) {
        self.level = level.uppercased()
    }

    func debug(_ message: String) { log("DEBUG", message) }
    func info(_ message: String) { log("INFO", message) }
    func warn(_ message: String) { log("WARN", message) }
    func error(_ message: String) { log("ERROR", message) }

    private func log(_ name: String, _ message: String) {
        let order = ["NONE": 0, "ERROR": 1, "WARN": 2, "INFO": 3, "DEBUG": 4]
        let configured = order[level] ?? 2
        let current = order[name] ?? 4
        if current <= configured {
            NSLog("[AlignApps][%@] %@", name, message)
        }
    }
}
