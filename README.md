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

## Android 对接流程

### 1. 环境要求

- `compileSdk = 36`、`minSdk >= 23`、JDK 17。
- 原生 SDK 已随插件内置（`android/libs/alignapps-sdk.jar`），无需任何 Maven 仓库，仅需默认的 `google()` 与 `mavenCentral()`。

在 `android/app/build.gradle.kts` 中确认（Flutter 模板通常已满足，若版本偏低需改大）：

```kotlin
android {
    compileSdk = 36
    defaultConfig {
        minSdk = 23
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
```

### 2. 权限

插件已自动合并以下权限，无需手动添加：

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="com.google.android.gms.permission.AD_ID" />
<uses-permission android:name="com.google.android.finsky.permission.BIND_GET_INSTALL_REFERRER_SERVICE" />
```

如不使用 Google 广告 ID，可在宿主 Manifest 中移除 `AD_ID`，并保持 `advertisingId=false`：

```xml
<uses-permission
    android:name="com.google.android.gms.permission.AD_ID"
    tools:node="remove" />
```

需在 `<manifest>` 上声明 `xmlns:tools="http://schemas.android.com/tools"`。

### 3. 初始化

Android 侧无需修改 `Application`，也无需在 `onCreate` 中初始化。直接在 Dart 中调用 `AlignappsFlutter.initialize(...)` 即可，参见「初始化与获取 installId」。

### 4. 深链 / App Links

在 `AndroidManifest.xml` 的 `MainActivity` 上添加入口 intent-filter（短链域名或自定义 scheme）：

```xml
<activity
    android:name=".MainActivity"
    android:launchMode="singleTop"
    android:exported="true">
    <!-- ...原有 LAUNCHER intent-filter... -->

    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="https" android:host="你的短链域名" />
    </intent-filter>
</activity>
```

- 插件已自动处理冷启动与 `onNewIntent` 收到的深链，无需额外代码。
- `launchMode` 使用 `singleTop`（Flutter 模板默认已是）。
- 若由第三方深链库自行处理，可再调用一次 `AlignappsFlutter.handleDeepLink(url)` 兜底。
- App Links 需在域名根目录发布 `assetlinks.json`。

### 5. 非 Google Play 安装（可选）

无 Install Referrer 的渠道，可在初始化时传入 `installToken`，或在拿到令牌后调用：

```dart
await AlignappsFlutter.setInstallToken('YOUR_INSTALL_TOKEN');
```

### 6. 调试与验证

```bash
adb logcat -s AlignApps
```

Release 包已内置消费者混淆规则，无需额外 ProGuard / R8 配置。

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
