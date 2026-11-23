# Changelog

## 0.3.2 - 2026-11-23

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
