# alignapps_flutter

Flutter bridge for the AlignApps attribution SDK. Supports Android and iOS.

## Platform support

- Android: bundles the native AlignApps Android SDK as `android/libs/alignapps-sdk.jar`.
- iOS: includes a native Swift implementation in `ios/Classes`.
- iOS 14.5+.
- iOS uses IDFV, IDFA (after ATT authorization), SKAdNetwork and Google On-device Conversion Measurement (`GoogleAdsOnDeviceConversion`).

## Installation

Add the plugin as a git dependency:

```yaml
dependencies:
  alignapps_flutter:
    git:
      url: https://github.com/jackleealready/alignapps_flutter.git
      ref: v0.3.1
```

Then run:

```bash
flutter pub get
cd ios && LANG=en_US.UTF-8 pod install --repo-update
```

Android requirements:

- `compileSdk = 36`, `minSdk >= 23`, JDK 17.
- The Android SDK is bundled as an AAR, so no Maven repository is required. Only the default `google()` and `mavenCentral()` repositories are needed.

## iOS requirements

- Host app `Info.plist` must include `NSUserTrackingUsageDescription`.
- Add Meta and Google SKAdNetwork identifiers to `SKAdNetworkItems`.
- The plugin depends on `GoogleAdsOnDeviceConversion` (3.0.0) and uses static frameworks.
- Add `-ObjC` and `-lc++` linker flags if you integrate the ODM framework manually.

## Initialize and track

```dart
import 'package:alignapps_flutter/alignapps_flutter.dart';

await AlignappsFlutter.initialize(
  const AlignappsConfig(
    appKey: 'YOUR_APP_KEY',
    serverUrl: 'https://attribution.example.com',
  ),
);

await AlignappsFlutter.track('register', {'method': 'google'});
await AlignappsFlutter.trackPurchase(
  orderId: 'order_1001',
  revenue: 4.99,
  currency: 'USD',
);
```

## ATT / SKAN

```dart
// Show the ATT prompt where your onboarding flow allows it.
await AlignappsFlutter.requestTrackingAuthorization();
final status = await AlignappsFlutter.getAttStatus();

// Manual conversion value update (automatic mapping is enabled by default).
await AlignappsFlutter.updateSkanConversionValue(3, 'high', true);

// Optional SKAN 4 update callback.
AlignappsFlutter.setSkanUpdatedCallback((data) {
  // {conversion_value, coarse_value, lock_window}
});
```

Default SKAN conversion values:

```text
install = 1 / low
register = 2 / medium
purchase = 3 / high
```

## Google ODM

The iOS plugin calls `GoogleAdsOnDeviceConversion` on first launch and caches `odm_info`. It is attached to events as `google_odm_info` and used by the AlignApps server for Google App Conversion API uploads.

## Firebase / GA4

Firebase Analytics is optional and is not required for AlignApps attribution. If you use it, log the same business events to GA4 and link GA4 to Google Ads so Google receives optimization signals. Keep AlignApps' Google App Conversion API as the attribution source to avoid double counting.
