import Foundation

enum AlignappsPrivacy {
    private static let lock = NSLock()
    private static var cachedConsentBaseUrl: String?
    private static var didResolve = false
    private static var didLogMissing = false

    /// Consent/tracking base URL declared in the SDK privacy manifest.
    ///
    /// `ios/inject_privacy_domain.sh` injects the host's consent domain into
    /// `alignapps_flutter_privacy.bundle/PrivacyInfo.xcprivacy`
    /// (`NSPrivacyTrackingDomains`). Reading it back keeps the runtime routing
    /// and the App Store declaration on the same value.
    static func consentBaseUrl() -> String? {
        lock.lock()
        defer { lock.unlock() }
        if didResolve {
            return cachedConsentBaseUrl
        }
        didResolve = true
        cachedConsentBaseUrl = resolveConsentBaseUrl()
        if cachedConsentBaseUrl == nil && !didLogMissing {
            didLogMissing = true
            NSLog("[AlignApps] consent domain missing from alignapps_flutter_privacy.bundle; falling back to serverUrl")
        }
        return cachedConsentBaseUrl
    }

    private static func resolveConsentBaseUrl() -> String? {
        guard let manifest = manifestUrl(),
              let data = try? Data(contentsOf: manifest),
              let object = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ),
              let plist = object as? [String: Any],
              let domains = plist["NSPrivacyTrackingDomains"] as? [String] else {
            return nil
        }

        guard let host = domains
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else {
            return nil
        }

        let normalized: String
        if host.hasPrefix("http://") || host.hasPrefix("https://") {
            normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            normalized = "https://\(host.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        }
        guard let url = URL(string: normalized), url.host != nil else {
            return nil
        }
        return normalized
    }

    private static func manifestUrl() -> URL? {
        let bundleName = "alignapps_flutter_privacy"
        let candidates: [URL?] = [
            Bundle.main.url(forResource: bundleName, withExtension: "bundle"),
            Bundle(for: AlignappsPrivacyBundleToken.self)
                .url(forResource: bundleName, withExtension: "bundle")
        ]

        for case let bundleURL? in candidates {
            guard let bundle = Bundle(url: bundleURL),
                  let manifest = bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") else {
                continue
            }
            return manifest
        }
        return nil
    }
}

private final class AlignappsPrivacyBundleToken: NSObject {}
