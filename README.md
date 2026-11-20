# alignapps_flutter

AlignApps 归因 SDK 的 Flutter 桥接插件，支持 Android 与 iOS。

## 平台支持

- Android：已内置 AlignApps 原生 Android SDK，位于 `android/libs/alignapps-sdk.jar`。
- iOS：`ios/Classes` 内含原生 Swift 实现。
- iOS 14.5+。
- iOS 使用 IDFV、IDFA（取得 ATT 授权后）、SKAdNetwork 以及 Google 设备端转化衡量（`GoogleAdsOnDeviceConversion`）。

## 安装接入

以 git 依赖方式引入插件：

```yaml
dependencies:
  alignapps_flutter:
    git:
      url: https://github.com/jackleealready/alignapps_flutter.git
      ref: v0.3.1
```

然后执行：

```bash
flutter pub get
cd ios && LANG=en_US.UTF-8 pod install --repo-update
```

Android 环境要求：

- `compileSdk = 36`、`minSdk >= 23`、JDK 17。
- 原生 SDK 已随插件内置，无需任何 Maven 仓库；仅需默认的 `google()` 与 `mavenCentral()`。

## iOS 配置要求

- 宿主 App 的 `Info.plist` 必须包含 `NSUserTrackingUsageDescription`。
- 在 `SKAdNetworkItems` 中加入 Meta 与 Google 的 SKAdNetwork 标识。
- 插件依赖 `GoogleAdsOnDeviceConversion`（3.0.0），并使用静态 framework。
- 如果手动集成 ODM framework，需要添加 `-ObjC` 和 `-lc++` 链接参数。

## 初始化与获取 installId

在 App 启动早期（如 `main()` 中）完成初始化，`initialize` 会返回本次安装的 `installId`：

```dart
import 'package:alignapps_flutter/alignapps_flutter.dart';

final installId = await AlignappsFlutter.initialize(
  const AlignappsConfig(
    appKey: 'YOUR_APP_KEY',
    serverUrl: 'https://attribution.example.com',
  ),
);
```

也可以在其他位置单独获取（未初始化时返回 `null`）：

```dart
final installId = await AlignappsFlutter.getInstallId();
```

`installId` 在单次安装内保持稳定，可传递给自己的业务服务端用于关联用户与归因数据。

## ATT / SKAN

```dart
// 在引导流程允许的时机弹出 ATT 授权弹窗。
await AlignappsFlutter.requestTrackingAuthorization();
final status = await AlignappsFlutter.getAttStatus();

// 手动更新转化值（默认已开启自动映射）。
await AlignappsFlutter.updateSkanConversionValue(3, 'high', true);

// 可选的 SKAN 4 更新回调。
AlignappsFlutter.setSkanUpdatedCallback((data) {
  // {conversion_value, coarse_value, lock_window}
});
```

默认 SKAN 转化值映射：

```text
install = 1 / low
register = 2 / medium
purchase = 3 / high
```

## Google ODM

iOS 插件会在首次启动时调用 `GoogleAdsOnDeviceConversion` 并缓存 `odm_info`，以 `google_odm_info` 字段附加到事件上，供 AlignApps 服务端向 Google App Conversion API 回传使用。

## Firebase / GA4

Firebase Analytics 为可选项，AlignApps 归因不依赖它。若同时使用，请把同样的业务事件也记录到 GA4，并将 GA4 关联到 Google Ads，以便 Google 获得优化信号。归因来源仍以 AlignApps 的 Google App Conversion API 为准，避免重复归因。
