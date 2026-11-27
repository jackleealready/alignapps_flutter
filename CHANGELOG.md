# Changelog

## 0.5.0 - 2026-11-27

- iOS: 隐私清单改为构建期自动注入。宿主在 `ios/Flutter/AlignappsPrivacyDomain.txt`（或 `ALIGNAPPS_TRACKING_DOMAIN`）提供独立归因域名，插件的 `ios/inject_privacy_domain.sh` 会把域名写入 `alignapps_flutter_privacy.bundle/PrivacyInfo.xcprivacy`。
- iOS: 缺少归因域名时构建直接失败，避免打出 tracking=true 但没有 domains 的不合规包。
- iOS: 宿主准备 2 个独立域名：`analytics.` 用作 `serverUrl`（实际上报），`consent.` 写入 `AlignappsPrivacyDomain.txt`（隐私清单的 tracking 域）；都不能用于业务。
- 文档：重写「iOS 隐私清单」为两个域名的接入方式；`PrivacyInfo.host-app.xcprivacy.template` 改为仅用于宿主自身追踪。

## 0.4.0 - 2026-11-27

- iOS: 隐私清单（`PrivacyInfo.xcprivacy`）不再内置固定追踪域名，宿主 App 需按模板声明自己的 `NSPrivacyTrackingDomains`（见 README「iOS 隐私清单」）。
- iOS: 新增 `ios/PrivacyInfo.host-app.xcprivacy.template` 供宿主 App 使用。
- 文档：更新 iOS 隐私清单接入步骤；初始化示例支持可选的 `--dart-define=ALIGNAPPS_SERVER_URL` / `ALIGNAPPS_APP_KEY` 注入。

## 0.3.2 - 2026-11-23

- Flutter: 新增 `AlignappsConfig.metaAnonId` 与 `AlignappsFlutter.setMetaAnonId()`，用于把 Meta App Events SDK 的 `anon_id` 随事件上送（ATT 拒绝下的 Meta 匹配信号）。
- iOS: 事件会携带 `meta_anon_id`，并通过 install refresh 接口更新服务端已有的安装归因。
- iOS: click parameters are recorded as `CLICK_MATCH` instead of `SAN`.
- iOS: non-install events wait for install attribution (`PENDING_ATTRIBUTION`) and are backfilled.
- iOS: Google App Conversion adds `gclid_only_request`, real consent (`ad_user_data`/`ad_personalization`/`eea`), OS build in User-Agent, and channel-based cross-network decision.
- iOS: ODM waits before first flush; ATT authorization refreshes server-side IDFA.
- iOS: Privacy Manifest declares advertising data, product interaction, purchase history and other usage data.
- Flutter: `AlignappsConsent` supports optional `adUserData`, `adPersonalization` and `eea`.

## 0.3.1 - 2026-11-20

- Bundle the Android SDK classes in `android/libs/alignapps-sdk.jar` so the plugin can be consumed as a Git dependency without any Maven repository.
- Merge the SDK required permissions into the plugin manifest and embed its consumer ProGuard rules.

## 0.3.0 - 2026-11-17

- Added iOS native implementation of the AlignApps attribution core.
- Added IDFA/IDFV/ATT device context for iOS.
- Added SKAdNetwork conversion value APIs and SKAN 4 callback.
- Added Google On-device Conversion Measurement (`odm_info`) collection.
- Added `requestTrackingAuthorization`, `getAttStatus`, `updateSkanConversionValue` and `disableSkanAttribution` Dart APIs.

## 0.2.0 - 2026-11-09

- Default `AlignappsConsent` now enables `analytics` and `advertisingId`.
- Updated native SDK dependency to `com.alignapps:alignapps-sdk:0.2.0`.

## 0.1.0 - 2026-11-06

- Initial Flutter bridge for the AlignApps Android SDK.
