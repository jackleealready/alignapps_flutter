# alignapps_flutter

AlignApps 归因 SDK 的 Flutter 桥接插件，支持 Android 与 iOS。

## 平台支持

- Android：内置 AlignApps 原生 Android SDK（`android/libs/alignapps-sdk.jar`）。
- iOS：`ios/Classes` 内含原生 Swift 实现，iOS 14.5+。
- iOS 使用 IDFV、IDFA（ATT 授权后）、SKAdNetwork、Google ODM；ATT 拒绝时用 Meta `anon_id` 提升匹配。

## 准备内容

### 通用

- 在 AlignApps 后台创建应用，拿到 `appKey`。
- 确定上报地址 `serverUrl`，例如 `analytics.example.com`（`example` 换成你的根域名）。

### iOS

- Xcode + CocoaPods；最低 iOS 14.5。
- 准备 2 个独立域名，都代理到 SDK 默认域名 `alignapps.win4me.vip`，且都不能用于业务：
  - `analytics.example.com`：主归因域，用作 `serverUrl`（实际上报）
  - `consent.example.com`：ATT 审核关联域，第三步写入 `ios/Flutter/AlignappsPrivacyDomain.txt`
- 准备 `Info.plist` 配置：ATT 说明、SKAdNetwork、Meta URL Scheme。
- 如果用 Meta：Meta App ID、Client Token（Meta for Developers 后台获取）。
- App Store Connect 的 App 记录和隐私信息（上架时用）。

### Android

- Android Studio / Gradle；`compileSdk = 36`、`minSdk >= 23`、JDK 17。
- Android 应用包名和签名。
- 不需要额外归因域名或隐私清单；`serverUrl` 用 `analytics.example.com`（`example` 换成你的根域名），和 iOS 相同。
- Google ODM 由插件自动集成，无需额外准备。

## 接入流程

### 第一步：添加依赖

`pubspec.yaml`：

```yaml
dependencies:
  alignapps_flutter:
    git:
      url: https://github.com/jackleealready/alignapps_flutter.git
      ref: v0.5.0

  # 仅 iOS 需要（Android 不会调用）
  app_tracking_transparency: ^2.0.7   # 请求 ATT
  facebook_app_events: ^0.34.0        # 只取 Meta anon_id
```

### 第二步：平台额外配置

#### iOS

在 `ios/Runner/Info.plist` 添加：

```xml
<key>NSUserTrackingUsageDescription</key>
<string>We use your advertising identifier to show you more relevant ads and improve our marketing performance.</string>

<key>SKAdNetworkItems</key>
<array>
  <dict><key>SKAdNetworkIdentifier</key><string>cstr6suwn9.skadnetwork</string></dict> <!-- Google -->
  <dict><key>SKAdNetworkIdentifier</key><string>v9wttpbfk9.skadnetwork</string></dict> <!-- Meta / Facebook -->
  <dict><key>SKAdNetworkIdentifier</key><string>n38lu8286q.skadnetwork</string></dict> <!-- Meta / Instagram -->
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
- Google ODM 已由插件自动集成，无需额外操作。
- 上面的 SKAdNetwork 只是 Google/Meta 的最小示例：Google 用 `cstr6suwn9`；Meta 至少需要 Facebook `v9wttpbfk9` + Instagram `n38lu8286q`。不是固定列表，投哪些平台就加入对应平台的完整列表；使用聚合/中介时还要加各中介平台的 ID。

#### Android

- `compileSdk = 36`、`minSdk >= 23`、JDK 17。
- 权限已由插件自动合并，无需手动添加。
- 调试：`adb logcat -s AlignApps`。

### 第三步：iOS 额外域名与隐私配置（仅 iOS）

准备 **2 个独立域名**，都代理到 SDK 默认域名（例如 `alignapps.win4me.vip`），且**都不能用于业务**：

- `analytics.<你的根域名>`，例如 `analytics.example.com`：主归因域，用作 `serverUrl`
- `consent.<你的根域名>`，例如 `consent.example.com`：ATT 审核关联域，写入隐私清单

创建 `ios/Flutter/AlignappsPrivacyDomain.txt`，写入 **consent 域**（只写 host）：

```text
consent.example.com
```

也可以设置 `ALIGNAPPS_TRACKING_DOMAIN=consent.example.com`。

构建时脚本会把 consent 域注入 `alignapps_flutter_privacy.bundle/PrivacyInfo.xcprivacy` 的 `NSPrivacyTrackingDomains`。运行时 SDK 从这份清单读取 consent 域：

- ATT 已授权且 `advertisingId=true` → 上报走 consent 域
- 其他情况 → 上报走 `serverUrl`（analytics 域）

这样拒绝 ATT 的用户不会走 consent 域，避免被系统断网。缺少该文件时 iOS 构建会直接失败。

> Android 跳过这一步；第五步的 `serverUrl` 同样用 `analytics.example.com`（`example` 换成你的根域名），不需要 consent 域。

### 第四步：安装依赖

```bash
flutter pub get
cd ios && LANG=en_US.UTF-8 pod install --repo-update
```

- Android 只需要执行 `flutter pub get`。
- iOS 必须重新 `pod install`，否则不会注册隐私域名注入脚本。

### 第五步：初始化 SDK

**初始化时机（重要）**：不要在 App 启动时直接初始化 SDK，推荐顺序：

1. 展示引导 / ATT 说明
2. 请求 ATT，并等待用户选择
3. 立即初始化 AlignApps（不要等整个 onboarding 结束）

这样 install 第一次上报时就带正确的 ATT 状态：

- 允许跟踪 → 带 IDFA，走 consent 域
- 不允许 → 不带 IDFA，走 `serverUrl`（analytics）

如果启动就初始化，install 可能先以“无 IDFA”上报；后续拿到 IDFA 只能靠服务端补（Meta 可重发，Google 的 install 不会补发）。用户拒绝 ATT 时也要照常初始化，不要因为没 IDFA 就不 init。

> 如果 App 依赖冷启动深链或启动即埋点，请在 init 前缓存，init 后再处理；延迟初始化会错过 init 之前的这些事件。

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
    // 1) 先做引导/ATT，再初始化；不要在 App 启动时直接 init。
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
      // 主归因域（analytics），用于真正的上报。
      serverUrl: 'https://analytics.example.com',
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

> `serverUrl` 填 `analytics.example.com`（`example` 换成你的根域名，真正的上报地址），iOS 和 Android 都用这个域。
>
> `ios/Flutter/AlignappsPrivacyDomain.txt` 里的 `consent.example.com` 是 iOS 的 consent 域：ATT 已授权且 `advertisingId=true` 时 SDK 会从隐私清单读取它并走这个域；其他情况走 `serverUrl`。不要把它填到 `serverUrl`，Android 也不会用它。

> 默认总是采集 `anon_id`：投不投 Meta 会变，采集本身没有副作用，这样不用为了开关反复发版。接入方只调 `initAlignApps()` 即可。

## 把 installId 传给业务服务端

注册、充值等业务事件由你的应用服务端上报，客户端只需要把 `installId` 交给服务端关联：

```dart
final installId = await AlignappsFlutter.getInstallId();
// 传给业务服务端，服务端上报 register / purchase 时带上 install_id
```

> 客户端不需要调用 `track` / `trackPurchase`；安装事件由 SDK 初始化时自动上报。

## 从 0.4.x 升级到 0.5.0

1. 把 `ref` 改成 `v0.5.0`（或你实际发布的分支/commit）。
2. 执行 `flutter pub get`；如果 `pubspec.lock` 仍锁定旧 commit，执行 `flutter pub upgrade alignapps_flutter`。
3. 按第三步创建 `ios/Flutter/AlignappsPrivacyDomain.txt`（写 consent 域）。
4. 重新 `pod install`。缺少该文件时 iOS 构建会失败（这是有意设计）。

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
