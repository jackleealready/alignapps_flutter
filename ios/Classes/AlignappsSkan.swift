import Foundation
import StoreKit

#if canImport(GoogleAdsOnDeviceConversion)
import GoogleAdsOnDeviceConversion
#endif

final class AlignappsSkan {
    private let storage: AlignappsStorage
    private let config: AlignappsConfig
    private let logger: AlignappsLogger
    private var disabled = false
    var onUpdated: (([String: String]) -> Void)?

    init(storage: AlignappsStorage, config: AlignappsConfig, logger: AlignappsLogger) {
        self.storage = storage
        self.config = config
        self.logger = logger
    }

    func register() {
        guard config.enableSkan, !disabled else { return }
        if #available(iOS 14.5, *) {
            SKAdNetwork.registerAppForAdNetworkAttribution()
        }
    }

    func disable() {
        disabled = true
    }

    func update(eventName: String) {
        guard config.enableSkan, !disabled else { return }
        guard let value = config.skanConversionValues[eventName] else { return }
        let coarse = coarseValue(for: eventName)
        update(value: value, coarse: coarse, lockWindow: eventName == "purchase")
    }

    func update(value: Int, coarse: String, lockWindow: Bool) {
        guard config.enableSkan, !disabled else { return }
        let safeValue = max(0, min(value, 63))
        let previous = storage.skanConversionValue
        guard safeValue >= previous else { return }
        storage.skanConversionValue = safeValue

        let payload: [String: String] = [
            "conversion_value": String(safeValue),
            "coarse_value": coarse,
            "lock_window": lockWindow ? "true" : "false"
        ]
        if #available(iOS 16.1, *) {
            let coarseValue: SKAdNetwork.CoarseConversionValue
            switch coarse.lowercased() {
            case "high": coarseValue = .high
            case "medium": coarseValue = .medium
            default: coarseValue = .low
            }
            SKAdNetwork.updatePostbackConversionValue(
                safeValue,
                coarseValue: coarseValue,
                lockWindow: lockWindow
            ) { [weak self] error in
                if let error {
                    self?.logger.warn("SKAN update failed: \(error.localizedDescription)")
                } else {
                    self?.onUpdated?(payload)
                }
            }
        } else if #available(iOS 14.5, *) {
            SKAdNetwork.updateConversionValue(safeValue)
            onUpdated?(payload)
        }
    }

    private func coarseValue(for eventName: String) -> String {
        switch eventName {
        case "purchase": return "high"
        case "register": return "medium"
        default: return "low"
        }
    }
}

final class AlignappsOdm {
    private let storage: AlignappsStorage
    private let config: AlignappsConfig
    private let logger: AlignappsLogger
    private var fetching = false

    init(storage: AlignappsStorage, config: AlignappsConfig, logger: AlignappsLogger) {
        self.storage = storage
        self.config = config
        self.logger = logger
    }

    func fetchIfNeeded(completion: ((String?) -> Void)? = nil) {
        if let cached = storage.googleOdmInfo, !cached.isEmpty {
            completion?(cached)
            return
        }
        guard config.enableOdm else {
            completion?(nil)
            return
        }
        #if canImport(GoogleAdsOnDeviceConversion)
        guard !fetching else {
            completion?(nil)
            return
        }
        fetching = true
        let launch = Date(timeIntervalSince1970: storage.firstLaunchAt)
        ConversionManager.sharedInstance.setFirstLaunchTime(launch)
        ConversionManager.sharedInstance.fetchAggregateConversionInfo(for: .installation) { [weak self] info, error in
            guard let self else { return }
            self.fetching = false
            if let error {
                self.logger.warn("ODM fetch failed: \(error.localizedDescription)")
                completion?(nil)
                return
            }
            let value = info?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value, !value.isEmpty {
                self.storage.googleOdmInfo = value
                completion?(value)
            } else {
                completion?(nil)
            }
        }
        #else
        completion?(nil)
        #endif
    }
}
