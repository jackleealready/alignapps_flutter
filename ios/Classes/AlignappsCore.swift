import AppTrackingTransparency
import Foundation
import UIKit

final class AlignappsCore {
    private let config: AlignappsConfig
    private let storage = AlignappsStorage()
    private let logger: AlignappsLogger
    private let queue: AlignappsQueue
    private let uploader: AlignappsUploader
    private let skan: AlignappsSkan
    private let odm: AlignappsOdm
    private let lock = NSLock()
    private let odmFlushLock = NSLock()

    private var initialized = false
    private var flushing = false
    private var flushTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    var onSkanUpdated: (([String: String]) -> Void)?

    init(config: AlignappsConfig) {
        self.config = config
        self.logger = AlignappsLogger(level: config.logLevel)
        self.queue = AlignappsQueue(storage: storage, maxSize: config.maxQueueSize)
        self.uploader = AlignappsUploader(config: config)
        self.skan = AlignappsSkan(storage: storage, config: config, logger: logger)
        self.odm = AlignappsOdm(storage: storage, config: config, logger: logger)
        self.skan.onUpdated = { [weak self] data in
            self?.onSkanUpdated?(data)
        }
    }

    private var trackingAllowed: Bool {
        storage.consent.advertisingId && AlignappsDevice.attStatus() == "authorized"
    }

    private func uploadBaseUrl() -> String {
        let allowed = trackingAllowed
        if allowed, let consentUrl = AlignappsPrivacy.consentBaseUrl() {
            logger.debug("upload_base_url=\(consentUrl) tracking_allowed=true")
            return consentUrl
        }
        logger.debug("upload_base_url=\(config.serverUrl) tracking_allowed=\(allowed)")
        return config.serverUrl
    }

    func start() -> String {
        lock.lock()
        defer { lock.unlock() }
        if initialized {
            return storage.installId
        }
        if !storage.hasConsent {
            storage.consent = config.initialConsent
        }
        if let token = config.installToken, !token.isEmpty {
            storage.installToken = token
        }
        if let anonId = config.metaAnonId?.trimmingCharacters(in: .whitespacesAndNewlines), !anonId.isEmpty {
            storage.metaAnonId = anonId
        }
        let installId = storage.installId
        _ = storage.firstLaunchAt
        let firstLaunch = storage.sessionStartedAt == 0
        if firstLaunch {
            storage.sessionId = UUID().uuidString.lowercased()
            storage.sessionStartedAt = Date().timeIntervalSince1970
        }
        if storage.installEventId == nil || queue.installEvent() == nil {
            let event = buildInstallEvent()
            storage.installEventId = event["event_id"] as? String
            queue.add(event)
        }
        if config.autoTrackSessions {
            if firstLaunch {
                queue.add(buildEvent(
                    name: "open",
                    type: "open",
                    properties: [:],
                    revenue: nil,
                    currency: nil,
                    attribution: nil
                ))
            } else {
                startSessionIfNeeded()
            }
        }
        registerLifecycle()
        startTimer()
        skan.register()
        skan.update(eventName: "install")
        initialized = true
        sanitizeIdfaIfNeeded()
        logger.info("AlignApps initialized installId=\(installId)")
        if config.enableOdm {
            var odmFlushed = false
            let finishOdm = { [weak self] in
                guard let self else { return }
                self.odmFlushLock.lock()
                if odmFlushed {
                    self.odmFlushLock.unlock()
                    return
                }
                odmFlushed = true
                self.odmFlushLock.unlock()
                // Avoid re-entering the main lock when ODM info is already cached.
                DispatchQueue.main.async { self.flush() }
            }
            odm.fetchIfNeeded { [weak self] info in
                guard let self else { return }
                if let info, let eventId = self.storage.installEventId {
                    self.queue.update(eventId: eventId) { event in
                        event["google_odm_info"] = info
                    }
                }
                finishOdm()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { finishOdm() }
        } else {
            flush()
        }
        return installId
    }

    var installId: String? {
        initialized ? storage.installId : nil
    }

    var isInitialized: Bool {
        initialized
    }

    func track(_ eventName: String, properties: [String: Any]) {
        guard initialized else {
            logger.warn("track called before initialization")
            return
        }
        guard isValidEventName(eventName), !isReserved(eventName) else {
            logger.warn("Invalid or reserved event name: \(eventName)")
            return
        }
        let type = eventName == "register" ? "register" : "custom"
        queue.add(buildEvent(
            name: eventName,
            type: type,
            properties: properties,
            revenue: nil,
            currency: nil,
            attribution: nil
        ))
        skan.update(eventName: eventName)
        flush()
    }

    func trackPurchase(_ orderId: String, revenue: Double, currency: String, properties: [String: Any]) {
        guard initialized else { return }
        guard !orderId.isEmpty, orderId.count <= 128, revenue.isFinite, revenue >= 0 else {
            logger.warn("Invalid purchase payload")
            return
        }
        let code = currency.uppercased()
        guard code.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
            logger.warn("Invalid purchase currency")
            return
        }
        var payload = properties
        payload["order_id"] = orderId
        queue.add(buildEvent(
            name: "purchase",
            type: "purchase",
            properties: payload,
            revenue: revenue,
            currency: code,
            attribution: nil
        ))
        skan.update(eventName: "purchase")
        flush()
    }

    func setConsent(_ consent: AlignappsConsent) {
        storage.consent = consent
        sanitizeIdfaIfNeeded()
        if consent.analytics {
            flush()
        }
    }

    func getConsent() -> AlignappsConsent {
        storage.consent
    }

    func setUserId(_ userId: String?) {
        storage.userId = userId?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setInstallToken(_ token: String) {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 1, normalized.count <= 256,
              normalized.range(of: "^[A-Za-z0-9._~-]+$", options: .regularExpression) != nil else {
            logger.warn("Invalid install token")
            return
        }
        storage.installToken = normalized
        guard let installId = storage.installEventId else { return }
        queue.update(eventId: installId) { event in
            var attribution = event["attribution"] as? [String: Any] ?? [:]
            attribution["install_token"] = normalized
            if attribution["click_id"] == nil {
                attribution["click_id"] = normalized
            }
            event["attribution"] = attribution
        }
        flush()
    }

    /// Set the anonymous ID generated by the Meta App Events SDK so it can be forwarded
    /// to Meta CAPI for matching when IDFA is unavailable (ATT denied).
    func setMetaAnonId(_ anonId: String) {
        let normalized = anonId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 1, normalized.count <= 255 else {
            logger.warn("Invalid Meta anon_id")
            return
        }
        storage.metaAnonId = normalized
        if let installEventId = storage.installEventId, queue.installEvent() != nil {
            queue.update(eventId: installEventId) { event in
                event["meta_anon_id"] = normalized
            }
        }
        uploader.refreshInstallDevice(
            installId: storage.installId,
            idfa: nil,
            idfv: nil,
            attStatus: nil,
            lat: nil,
            metaAnonId: normalized,
            baseUrl: uploadBaseUrl()
        )
        flush()
    }

    @discardableResult
    func handleDeepLink(_ url: String) -> Bool {
        guard let components = URLComponents(string: url) else { return false }
        let params = parseAttribution(components)
        guard !params.isEmpty else { return false }
        if let installId = storage.installEventId, queue.installEvent() != nil {
            queue.update(eventId: installId) { event in
                var attribution = event["attribution"] as? [String: Any] ?? [:]
                attribution.merge(params) { _, new in new }
                if attribution["click_id"] == nil {
                    attribution["click_id"] = attribution["aa_click_id"] ?? attribution["alignapps_click_id"]
                }
                event["attribution"] = attribution
            }
        } else {
            queue.add(buildEvent(
                name: "deep_link_open",
                type: "deep_link",
                properties: ["link_scheme": components.scheme ?? "", "link_host": components.host ?? ""],
                revenue: nil,
                currency: nil,
                attribution: params
            ))
        }
        flush()
        return true
    }

    func flush() {
        lock.lock()
        if flushing || !storage.consent.analytics {
            lock.unlock()
            return
        }
        flushing = true
        lock.unlock()

        let events = queue.all()
        guard !events.isEmpty else {
            lock.lock()
            flushing = false
            lock.unlock()
            return
        }
        let batch = Array(events.prefix(50))
        uploader.upload(
            events: batch,
            installId: storage.installId,
            baseUrl: uploadBaseUrl()
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                let ids = Set(batch.compactMap { $0["event_id"] as? String })
                self.queue.remove(eventIds: ids)
            case .permanent(let reason):
                self.logger.error("Dropping rejected events: \(reason)")
                let ids = Set(batch.compactMap { $0["event_id"] as? String })
                self.queue.remove(eventIds: ids)
            case .retryable(let reason):
                self.logger.warn("Event upload will be retried: \(reason)")
            }
            self.lock.lock()
            self.flushing = false
            self.lock.unlock()
            if case .success = result {
                self.flush()
            }
        }
    }

    func setLogLevel(_ level: String) {
        logger.setLevel(level)
    }

    func requestTrackingAuthorization(completion: @escaping (Int) -> Void) {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { [weak self] status in
                if let self {
                    self.refreshIdfa()
                }
                completion(Int(status.rawValue))
            }
        } else {
            completion(3)
        }
    }

    func getAttStatus() -> String {
        AlignappsDevice.attStatus()
    }

    func deviceInfo() -> [String: Any] {
        var info = AlignappsDevice.snapshot(consent: storage.consent)
        info["install_id"] = storage.installId
        return info
    }

    func updateSkanConversionValue(value: Int, coarse: String, lockWindow: Bool) {
        skan.update(value: value, coarse: coarse, lockWindow: lockWindow)
    }

    func disableSkanAttribution() {
        skan.disable()
    }

    private func refreshIdfa() {
        let device = AlignappsDevice.snapshot(consent: storage.consent)
        if let installEventId = storage.installEventId, queue.installEvent() != nil {
            queue.update(eventId: installEventId) { event in
                event["device"] = device
            }
        }
        sanitizeIdfaIfNeeded()
        if storage.consent.analytics {
            uploader.refreshInstallDevice(
                installId: storage.installId,
                idfa: device["idfa"] as? String,
                idfv: device["idfv"] as? String,
                attStatus: device["att_status"] as? String,
                lat: device["lat"] as? Bool,
                metaAnonId: storage.metaAnonId,
                baseUrl: uploadBaseUrl()
            )
        }
    }

    private func sanitizeIdfaIfNeeded() {
        guard !trackingAllowed else { return }
        let events = queue.all()
        for event in events {
            guard let eventId = event["event_id"] as? String else { continue }
            queue.update(eventId: eventId) { item in
                if var device = item["device"] as? [String: Any] {
                    device.removeValue(forKey: "idfa")
                    item["device"] = device
                }
            }
        }
    }

    private func buildInstallEvent() -> [String: Any] {
        var attribution: [String: Any] = [:]
        if let token = storage.installToken, !token.isEmpty {
            attribution["install_token"] = token
            attribution["click_id"] = token
        }
        return buildEvent(
            name: "install",
            type: "install",
            properties: ["first_open": true],
            revenue: nil,
            currency: nil,
            attribution: attribution.isEmpty ? nil : attribution
        )
    }

    private func buildEvent(
        name: String,
        type: String,
        properties: [String: Any],
        revenue: Double?,
        currency: String?,
        attribution: [String: Any]?
    ) -> [String: Any] {
        let now = Date()
        var event: [String: Any] = [
            "event_id": UUID().uuidString.lowercased(),
            "event_name": name,
            "event_type": type,
            "occurred_at": AlignappsTime.iso8601(now),
            "timestamp_ms": AlignappsTime.ms(now),
            "session_id": storage.sessionId,
            "install_id": storage.installId,
            "properties": properties,
            "device": AlignappsDevice.snapshot(consent: storage.consent)
        ]
        if let userId = storage.userId, !userId.isEmpty {
            event["user_id"] = userId
        }
        if let revenue {
            event["revenue"] = revenue
        }
        if let currency {
            event["currency"] = currency
        }
        if let attribution, !attribution.isEmpty {
            event["attribution"] = attribution
        }
        if let odm = storage.googleOdmInfo, !odm.isEmpty {
            event["google_odm_info"] = odm
        }
        if let metaAnonId = storage.metaAnonId, !metaAnonId.isEmpty {
            event["meta_anon_id"] = metaAnonId
        }
        let adConsent = storage.consent.toAdConsentMap()
        if !adConsent.isEmpty {
            event["consent"] = adConsent
        }
        return event
    }

    private func startSessionIfNeeded() {
        let now = Date().timeIntervalSince1970
        let last = storage.sessionStartedAt
        let expired = last == 0 || now - last > config.sessionTimeoutSeconds
        guard expired else { return }
        storage.sessionId = UUID().uuidString.lowercased()
        storage.sessionStartedAt = now
        queue.add(buildEvent(
            name: "open",
            type: "open",
            properties: [:],
            revenue: nil,
            currency: nil,
            attribution: nil
        ))
        flush()
    }

    private func registerLifecycle() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startSessionIfNeeded()
        })
    }

    private func startTimer() {
        guard flushTimer == nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flushTimer = Timer.scheduledTimer(
                withTimeInterval: self.config.flushIntervalSeconds,
                repeats: true
            ) { [weak self] _ in
                self?.flush()
            }
        }
    }

    private func parseAttribution(_ components: URLComponents) -> [String: Any] {
        let allowed: Set<String> = [
            "alignapps_click_id", "aa_click_id", "gclid", "fbclid", "ttclid",
            "gbraid", "wbraid", "campaign_id", "adset_id", "ad_id", "adgroup_id",
            "creative_id", "channel", "source", "sub1", "sub2", "sub3", "sub4", "sub5"
        ]
        var result: [String: Any] = [:]
        for item in components.queryItems ?? [] {
            let key = item.name.lowercased()
            guard key.count <= 64, let value = item.value, !value.isEmpty else { continue }
            let isAllowed = allowed.contains(key) || (key.hasPrefix("utm_") && key.count <= 32)
            guard isAllowed else { continue }
            if key == "aa_click_id" || key == "alignapps_click_id" {
                guard value.range(of: "^[A-Za-z0-9._~-]{1,256}$", options: .regularExpression) != nil else { continue }
            }
            result[key] = String(value.prefix(512))
            if result.count >= 50 { break }
        }
        return result
    }

    private func isValidEventName(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z][A-Za-z0-9_]{0,63}$", options: .regularExpression) != nil
    }

    private func isReserved(_ name: String) -> Bool {
        ["install", "open", "deep_link_open", "purchase"].contains(name)
    }
}
