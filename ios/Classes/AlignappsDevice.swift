import AdSupport
import AppTrackingTransparency
import Darwin
import Foundation
import UIKit

struct AlignappsDevice {
    static let sdkVersion = "0.3.2"

    static func attStatus() -> String {
        if #available(iOS 14, *) {
            switch ATTrackingManager.trackingAuthorizationStatus {
            case .authorized: return "authorized"
            case .denied: return "denied"
            case .restricted: return "restricted"
            case .notDetermined: return "not_determined"
            @unknown default: return "not_determined"
            }
        }
        return ASIdentifierManager.shared().isAdvertisingTrackingEnabled ? "authorized" : "denied"
    }

    static func idfa(consent: AlignappsConsent) -> String? {
        guard consent.advertisingId, attStatus() == "authorized" else { return nil }
        guard ASIdentifierManager.shared().isAdvertisingTrackingEnabled else { return nil }
        let value = ASIdentifierManager.shared().advertisingIdentifier.uuidString
        if value.isEmpty || value == "00000000-0000-0000-0000-000000000000" {
            return nil
        }
        return value
    }

    static func snapshot(consent: AlignappsConsent) -> [String: Any] {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let locale = Locale.current.identifier.replacingOccurrences(of: "-", with: "_")
        let timezone = TimeZone.current.identifier
        let status = attStatus()
        let country = countryCode()
        var device: [String: Any] = [
            "platform": "ios",
            "app_package": bundle.bundleIdentifier ?? "",
            "app_version": version,
            "app_build": build,
            "os_version": UIDevice.current.systemVersion,
            "os_build": osBuild() ?? "",
            "manufacturer": "Apple",
            "model": machineName(),
            "locale": locale,
            "timezone": timezone,
            "user_agent": "AlignApps-iOS/\(sdkVersion)",
            "sdk_version": sdkVersion,
            "att_status": status,
            "lat": status != "authorized"
        ]
        if let idfv = UIDevice.current.identifierForVendor?.uuidString {
            device["idfv"] = idfv
        }
        if let idfaValue = idfa(consent: consent) {
            device["idfa"] = idfaValue
        }
        if let country {
            device["country_code"] = country
        }
        return device
    }

    static func countryCode() -> String? {
        if #available(iOS 16, *) {
            return Locale.current.region?.identifier
        }
        return Locale.current.regionCode
    }

    private static func osBuild() -> String? {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        let value = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func machineName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
