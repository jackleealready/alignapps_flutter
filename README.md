# alignapps_flutter

AlignApps 归因 SDK 的 Flutter 桥接插件，支持 Android 与 iOS。

## 平台支持

- Android：内置 AlignApps 原生 Android SDK（`android/libs/alignapps-sdk.jar`）。
- iOS：`ios/Classes` 内含原生 Swift 实现，iOS 14.5+。
- iOS 使用 IDFV、IDFA（ATT 授权后）、SKAdNetwork、Google ODM；ATT 拒绝时用 Meta `anon_id` 提升匹配。

## 安装

```yaml
dependencies:
  alignapps_flutter:
    git:
      url: https://github.com/jackleealready/alignapps_flutter.git
      ref: v0.4.0
  # 仅 iOS 用到（Android 不会调用，也不会初始化）
  app_tracking_transparency: ^2.0.7   # 请求 ATT
  facebook_app_events: ^0.34.0        # 只取 Meta anon_id
```

```bash
flutter pub get
cd ios && LANG=en_US.UTF-8 pod install --repo-update
```

## 一条统一初始化方法（直接复制）

Android 和 iOS 的差异都封装在这个方法里，接入方只需要调用 `initAlignApps()`：

```dart
import 'dart:async';
import 'dart:io';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:alignapps_flutter/alignapps_flutter.dart';

/// Android / iOS 共用，内部自动处理平台差异与 anon_id 重试。
Future<void> initAlignApps({
  /// anon_id 缺失时每 3 秒重试一次。
  Duration retryInterval = const Duration(seconds: 3),
  int maxRetries = 10,
}) async {
  String? metaAnonId;

  if (Platform.isIOS) {
    // 1) ATT 必须在初始化 AlignApps 之前。
    await AppTrackingTransparency.requestTrackingAuthorization();

    // 2) 只拿 anon_id，不上报事件、不采集 IDFA。
    final fb = FacebookAppEvents();
    await fb.setAutoLogAppEventsEnabled(false);
    await fb.setAdvertiserIdCollectionEnabled(false);
    await fb.initializeSdk();
    metaAnonId = await _readAnonId(fb);
  }

  // 3) 初始化 AlignApps（Android 到这就结束）。
  await AlignappsFlutter.initialize(
    AlignappsConfig(
      appKey: 'YOUR_APP_KEY',
      serverUrl: 'https://attribution.example.com',
      metaAnonId: metaAnonId,
      initialConsent: const AlignappsConsent(
        analytics: true,
        advertisingId: true,
      ),
    ),
  );

  // 4) 初始化时没拿到：每 3 秒重试，拿到后补传（不阻塞 install）。
  if (Platform.isIOS && metaAnonId == null) {
    unawaited(_retryMetaAnonId(retryInterval, maxRetries));
  }
}

Future<String?> _readAnonId(FacebookAppEvents fb) async {
  final id = await fb.getAnonymousId();
  return (id == null || id.isEmpty) ? null : id;
}

Future<void> _retryMetaAnonId(Duration interval, int maxRetries) async {
  final fb = FacebookAppEvents();
  for (var i = 0; i < maxRetries; i++) {
    await Future.delayed(interval);
    final id = await _readAnonId(fb);
    if (id != null) {
      await AlignappsFlutter.setMetaAnonId(id);
      return;
    }
  }
}
```

> `serverUrl` 直接填你自己的域名（或 CNAME / 反代地址）即可，**不需要任何构建参数**；每个商户用各自域名，生产不要共用同一个测试域名。上面的 `attribution.example.com` 只是占位。

> 默认总是采集 `anon_id`：投不投 Meta 会变，采集本身没有副作用，这样不用为了开关反复发版。接入方只调 `initAlignApps()` 即可。

## Android 额外配置

环境：`compileSdk = 36`、`minSdk >= 23`、JDK 17。

权限已由插件自动合并，无需手动添加。调试：`adb logcat -s AlignApps`。

## iOS 额外配置（Info.plist）

```xml
<key>NSUserTrackingUsageDescription</key>
<string>此标识用于广告归因和投放效果分析。</string>

<key>SKAdNetworkItems</key>
<array>
  <dict><key>SKAdNetworkIdentifier</key><string>cstr6suwn9.skadnetwork</string></dict> <!-- Google -->
  <dict><key>SKAdNetworkIdentifier</key><string>v9wttpbfk9.skadnetwork</string></dict> <!-- Meta -->
</array>

<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array><string>fb[APP_ID]</string></array>
  </dict>
</array>
<key>FacebookAppID</key>
<string>[APP_ID]</string>
<key>FacebookClientToken</key>
<string>[CLIENT_TOKEN]</string>
<key>FacebookDisplayName</key>
<string>[APP_NAME]</string>
```

- `[APP_ID]`、`[CLIENT_TOKEN]` 在 Meta for Developers 后台获取。
- Google ODM 已由插件自动集成，**无需额外操作**。

## iOS 隐私清单（必须）

1. 复制 `ios/PrivacyInfo.host-app.xcprivacy.template` 到你的 `ios/Runner/PrivacyInfo.xcprivacy`（若已有 App 级隐私清单，把 `NSPrivacyTrackingDomains` 合并进去）。
2. 在 Xcode 中把该文件加入 App target 的 **Copy Bundle Resources**。
3. 将 `__ALIGNAPPS_TRACKING_DOMAIN__` 替换为你 `serverUrl` 的域名（你自己的域名 / CNAME），例如 `sdk.yourgame.com`。
4. 域名需与 `AlignappsConfig.serverUrl` 的 host 一致；生产环境使用自己的域名。

## 把 installId 传给业务服务端

注册、充值等业务事件由你的应用服务端上报，客户端只需要把 `installId` 交给服务端关联：

```dart
final installId = await AlignappsFlutter.getInstallId();
// 传给业务服务端，服务端上报 register / purchase 时带上 install_id
```

> 客户端不需要调用 `track` / `trackPurchase`；安装事件由 SDK 初始化时自动上报。

## 常见问题

**Q：FacebookAppID 会变怎么办？**
它只在接入方自己的 `Info.plist` 里，AlignApps 不写死。换 Meta App 时改 `FacebookAppID` / `FacebookClientToken` / `fb[APP_ID]` 即可，Dart 代码不用动；`anon_id` 读取逻辑自动适配。

**Q：可以只拿 anon_id、不让 Facebook 上报事件吗？**
可以。方法里已经：
- `setAutoLogAppEventsEnabled(false)`：关闭 Meta 自动事件上报；
- `setAdvertiserIdCollectionEnabled(false)`：不让 FBSDK 采集 IDFA。
事件统一由 AlignApps 上送。注意 FBSDK 初始化本身仍会初始化 SDK，但不会记录 app 事件。

**Q：以后不投 Meta 了怎么办？**
不用改代码。`anon_id` 会一直采集，但不投 Meta 时平台不会用到它，没有副作用；如果某天想彻底移除 Meta SDK，再删掉 iOS 那段和对应依赖即可。

**Q：需要接 Firebase / GA4 吗？**
不需要，与 AlignApps 归因无关。
