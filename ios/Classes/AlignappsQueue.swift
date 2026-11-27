import Foundation

final class AlignappsQueue {
    private let storage: AlignappsStorage
    private let maxSize: Int
    private let lock = NSLock()

    init(storage: AlignappsStorage, maxSize: Int) {
        self.storage = storage
        self.maxSize = max(10, maxSize)
    }

    func add(_ event: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        var events = storage.loadEvents()
        if let eventId = event["event_id"] as? String,
           let index = events.firstIndex(where: { ($0["event_id"] as? String) == eventId }) {
            events[index] = event
        } else {
            events.append(event)
        }
        if events.count > maxSize {
            let install = events.filter { ($0["event_type"] as? String) == "install" }
            let others = events.filter { ($0["event_type"] as? String) != "install" }
            events = Array(install.suffix(1)) + Array(others.suffix(maxSize - min(install.count, 1)))
        }
        storage.saveEvents(events)
    }

    func update(eventId: String, mutate: (inout [String: Any]) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var events = storage.loadEvents()
        guard let index = events.firstIndex(where: { ($0["event_id"] as? String) == eventId }) else { return }
        var event = events[index]
        mutate(&event)
        events[index] = event
        storage.saveEvents(events)
    }

    func all() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return storage.loadEvents()
    }

    func remove(eventIds: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        let events = storage.loadEvents().filter {
            guard let eventId = $0["event_id"] as? String else { return true }
            return !eventIds.contains(eventId)
        }
        storage.saveEvents(events)
    }

    func installEvent() -> [String: Any]? {
        all().first { ($0["event_type"] as? String) == "install" }
    }
}

enum AlignappsUploadResult {
    case success(Int)
    case retryable(String)
    case permanent(String)
}

final class AlignappsUploader {
    private let config: AlignappsConfig
    private let session: URLSession

    init(config: AlignappsConfig) {
        self.config = config
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = config.requestTimeoutSeconds
        configuration.timeoutIntervalForResource = config.requestTimeoutSeconds
        self.session = URLSession(configuration: configuration)
    }

    func upload(
        events: [[String: Any]],
        installId: String,
        baseUrl: String,
        completion: @escaping (AlignappsUploadResult) -> Void
    ) {
        guard !events.isEmpty else {
            completion(.success(0))
            return
        }
        guard let url = URL(string: baseUrl + "/api/v1/sdk/events") else {
            completion(.permanent("Invalid serverUrl"))
            return
        }
        let payload: [String: Any] = [
            "app_key": config.appKey,
            "install_id": installId,
            "sdk_version": AlignappsDevice.sdkVersion,
            "platform": "ios",
            "sent_at": AlignappsTime.iso8601(Date()),
            "events": events
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.permanent("Unable to serialize events"))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(config.appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue(AlignappsDevice.sdkVersion, forHTTPHeaderField: "X-SDK-Version")
        request.setValue("ios", forHTTPHeaderField: "X-Platform")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AlignApps-iOS/\(AlignappsDevice.sdkVersion)", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { _, response, error in
            if let error {
                completion(.retryable(error.localizedDescription))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.retryable("No HTTP response"))
                return
            }
            if (200..<300).contains(http.statusCode) {
                completion(.success(events.count))
            } else if [408, 425, 429, 500, 501, 502, 503, 504, 507, 509].contains(http.statusCode) {
                completion(.retryable("HTTP \(http.statusCode)"))
            } else {
                completion(.permanent("HTTP \(http.statusCode)"))
            }
        }.resume()
    }

    func refreshInstallDevice(
        installId: String,
        idfa: String?,
        idfv: String?,
        attStatus: String?,
        lat: Bool?,
        metaAnonId: String?,
        baseUrl: String
    ) {
        guard let url = URL(string: baseUrl + "/api/v1/sdk/install-attributions/refresh") else {
            return
        }
        var payload: [String: Any] = [
            "app_key": config.appKey,
            "install_id": installId,
            "platform": "ios"
        ]
        if let idfa, !idfa.isEmpty { payload["idfa"] = idfa }
        if let idfv, !idfv.isEmpty { payload["idfv"] = idfv }
        if let attStatus, !attStatus.isEmpty { payload["att_status"] = attStatus }
        if let lat { payload["lat"] = lat }
        if let metaAnonId, !metaAnonId.isEmpty { payload["meta_anon_id"] = metaAnonId }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(config.appKey, forHTTPHeaderField: "X-App-Key")
        request.setValue(AlignappsDevice.sdkVersion, forHTTPHeaderField: "X-SDK-Version")
        request.setValue("ios", forHTTPHeaderField: "X-Platform")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AlignApps-iOS/\(AlignappsDevice.sdkVersion)", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { _, _, _ in }.resume()
    }
}

enum AlignappsTime {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func iso8601(_ date: Date) -> String {
        formatter.string(from: date)
    }

    static func ms(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }
}
