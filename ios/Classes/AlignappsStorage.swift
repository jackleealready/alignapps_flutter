import Foundation

final class AlignappsStorage {
    private let defaults = UserDefaults.standard
    private let lock = NSLock()

    private enum Keys {
        static let installId = "com.alignapps.installId"
        static let installEventId = "com.alignapps.installEventId"
        static let sessionId = "com.alignapps.sessionId"
        static let sessionStartedAt = "com.alignapps.sessionStartedAt"
        static let userId = "com.alignapps.userId"
        static let installToken = "com.alignapps.installToken"
        static let consent = "com.alignapps.consent"
        static let queue = "com.alignapps.eventQueue"
        static let googleOdmInfo = "com.alignapps.googleOdmInfo"
        static let metaAnonId = "com.alignapps.metaAnonId"
        static let firstLaunchAt = "com.alignapps.firstLaunchAt"
        static let skanConversionValue = "com.alignapps.skanConversionValue"
    }

    var installId: String {
        lock.lock()
        defer { lock.unlock() }
        if let value = defaults.string(forKey: Keys.installId), !value.isEmpty {
            return value
        }
        let value = UUID().uuidString.lowercased()
        defaults.set(value, forKey: Keys.installId)
        return value
    }

    var installEventId: String? {
        get { defaults.string(forKey: Keys.installEventId) }
        set { defaults.set(newValue, forKey: Keys.installEventId) }
    }

    var sessionId: String {
        get {
            if let value = defaults.string(forKey: Keys.sessionId), !value.isEmpty {
                return value
            }
            let value = UUID().uuidString.lowercased()
            defaults.set(value, forKey: Keys.sessionId)
            return value
        }
        set { defaults.set(newValue, forKey: Keys.sessionId) }
    }

    var sessionStartedAt: TimeInterval {
        get { defaults.double(forKey: Keys.sessionStartedAt) }
        set { defaults.set(newValue, forKey: Keys.sessionStartedAt) }
    }

    var userId: String? {
        get { defaults.string(forKey: Keys.userId) }
        set { defaults.set(newValue, forKey: Keys.userId) }
    }

    var installToken: String? {
        get { defaults.string(forKey: Keys.installToken) }
        set { defaults.set(newValue, forKey: Keys.installToken) }
    }

    var hasConsent: Bool {
        defaults.object(forKey: Keys.consent) != nil
    }

    var consent: AlignappsConsent {
        get {
            guard let map = defaults.dictionary(forKey: Keys.consent) else {
                return AlignappsConsent()
            }
            return AlignappsConsent.from(map)
        }
        set { defaults.set(newValue.toMap(), forKey: Keys.consent) }
    }

    var googleOdmInfo: String? {
        get { defaults.string(forKey: Keys.googleOdmInfo) }
        set { defaults.set(newValue, forKey: Keys.googleOdmInfo) }
    }

    var metaAnonId: String? {
        get { defaults.string(forKey: Keys.metaAnonId) }
        set { defaults.set(newValue, forKey: Keys.metaAnonId) }
    }

    var firstLaunchAt: TimeInterval {
        get {
            let value = defaults.double(forKey: Keys.firstLaunchAt)
            if value > 0 {
                return value
            }
            let now = Date().timeIntervalSince1970
            defaults.set(now, forKey: Keys.firstLaunchAt)
            return now
        }
        set { defaults.set(newValue, forKey: Keys.firstLaunchAt) }
    }

    var skanConversionValue: Int {
        get { defaults.integer(forKey: Keys.skanConversionValue) }
        set { defaults.set(newValue, forKey: Keys.skanConversionValue) }
    }

    func loadEvents() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: Keys.queue),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return json
    }

    func saveEvents(_ events: [[String: Any]]) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? JSONSerialization.data(withJSONObject: events) else { return }
        defaults.set(data, forKey: Keys.queue)
    }
}
