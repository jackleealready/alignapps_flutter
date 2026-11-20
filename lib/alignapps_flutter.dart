import 'package:flutter/services.dart';

enum AlignappsLogLevel { none, error, warn, info, debug }

class AlignappsConsent {
  const AlignappsConsent({
    this.analytics = true,
    this.advertisingId = true,
  });

  final bool analytics;
  final bool advertisingId;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'analytics': analytics,
      'advertisingId': advertisingId,
    };
  }

  factory AlignappsConsent.fromMap(Map<Object?, Object?> map) {
    return AlignappsConsent(
      analytics: map['analytics'] as bool? ?? true,
      advertisingId: map['advertisingId'] as bool? ?? true,
    );
  }
}

class AlignappsConfig {
  const AlignappsConfig({
    required this.appKey,
    required this.serverUrl,
    this.logLevel = AlignappsLogLevel.warn,
    this.enableInstallReferrer = true,
    this.autoTrackSessions = true,
    this.sessionTimeoutSeconds = 1800,
    this.flushIntervalSeconds = 15,
    this.maxQueueSize = 500,
    this.requestTimeoutSeconds = 15,
    this.debug = false,
    this.initialConsent = const AlignappsConsent(),
    this.installToken,
    this.enableSkan = true,
    this.enableOdm = true,
    this.skanConversionValues = const <String, int>{
      'install': 1,
      'register': 2,
      'purchase': 3,
    },
  });

  final String appKey;
  final String serverUrl;
  final AlignappsLogLevel logLevel;
  final bool enableInstallReferrer;
  final bool autoTrackSessions;
  final int sessionTimeoutSeconds;
  final int flushIntervalSeconds;
  final int maxQueueSize;
  final int requestTimeoutSeconds;
  final bool debug;
  final AlignappsConsent initialConsent;
  final String? installToken;
  final bool enableSkan;
  final bool enableOdm;
  final Map<String, int> skanConversionValues;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'appKey': appKey,
      'serverUrl': serverUrl,
      'logLevel': logLevel.name.toUpperCase(),
      'enableInstallReferrer': enableInstallReferrer,
      'autoTrackSessions': autoTrackSessions,
      'sessionTimeoutSeconds': sessionTimeoutSeconds,
      'flushIntervalSeconds': flushIntervalSeconds,
      'maxQueueSize': maxQueueSize,
      'requestTimeoutSeconds': requestTimeoutSeconds,
      'debug': debug,
      'initialConsent': initialConsent.toMap(),
      if (installToken != null) 'installToken': installToken,
      'enableSkan': enableSkan,
      'enableOdm': enableOdm,
      'skanConversionValues': skanConversionValues,
    };
  }
}

class AlignappsFlutter {
  static const MethodChannel _channel = MethodChannel('com.alignapps/flutter');
  static void Function(Map<String, String> data)? _skanUpdatedCallback;
  static bool _methodHandlerInstalled = false;

  static void _installMethodHandler() {
    if (_methodHandlerInstalled) return;
    _methodHandlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'skanUpdated') {
        final raw = call.arguments as Map<Object?, Object?>? ?? const {};
        final data = raw.map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
        );
        _skanUpdatedCallback?.call(data);
      }
      return null;
    });
  }

  static Future<int> requestTrackingAuthorization() async {
    final value = await _channel.invokeMethod<int>('requestTrackingAuthorization');
    return value ?? 0;
  }

  static Future<String> getAttStatus() async {
    final value = await _channel.invokeMethod<String>('getAttStatus');
    return value ?? 'not_determined';
  }

  static Future<Map<String, Object?>> getDeviceInfo() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>('getDeviceInfo');
    if (value == null) return <String, Object?>{};
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  static Future<void> updateSkanConversionValue(
    int conversionValue,
    String coarseValue,
    bool lockWindow,
  ) {
    return _channel.invokeMethod<void>('updateSkanConversionValue', <String, Object?>{
      'conversionValue': conversionValue,
      'coarseValue': coarseValue,
      'lockWindow': lockWindow,
    });
  }

  static Future<void> disableSkanAttribution() {
    return _channel.invokeMethod<void>('disableSkanAttribution');
  }

  static void setSkanUpdatedCallback(
    void Function(Map<String, String> data)? callback,
  ) {
    _installMethodHandler();
    _skanUpdatedCallback = callback;
  }

  static Future<String> initialize(AlignappsConfig config) async {
    final installId = await _channel.invokeMethod<String>(
      'initialize',
      config.toMap(),
    );
    if (installId == null || installId.isEmpty) {
      throw PlatformException(
        code: 'initialize_failed',
        message: 'AlignApps did not return an install id',
      );
    }
    return installId;
  }

  static Future<void> track(
    String eventName, [
    Map<String, Object?> properties = const <String, Object?>{},
  ]) {
    return _channel.invokeMethod<void>('track', <String, Object?>{
      'eventName': eventName,
      'properties': properties,
    });
  }

  static Future<void> trackPurchase({
    required String orderId,
    required double revenue,
    required String currency,
    Map<String, Object?> properties = const <String, Object?>{},
  }) {
    return _channel.invokeMethod<void>('trackPurchase', <String, Object?>{
      'orderId': orderId,
      'revenue': revenue,
      'currency': currency,
      'properties': properties,
    });
  }

  static Future<void> setConsent(AlignappsConsent consent) {
    return _channel.invokeMethod<void>('setConsent', consent.toMap());
  }

  static Future<AlignappsConsent> getConsent() async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      'getConsent',
    );
    return AlignappsConsent.fromMap(value ?? const <Object?, Object?>{});
  }

  static Future<void> setUserId(String? userId) {
    return _channel.invokeMethod<void>('setUserId', <String, Object?>{
      'userId': userId,
    });
  }

  static Future<void> setInstallToken(String token) {
    return _channel.invokeMethod<void>('setInstallToken', <String, Object?>{
      'token': token,
    });
  }

  static Future<bool> handleDeepLink(String url) async {
    final handled = await _channel.invokeMethod<bool>(
      'handleDeepLink',
      <String, Object?>{'url': url},
    );
    return handled ?? false;
  }

  static Future<void> flush() {
    return _channel.invokeMethod<void>('flush');
  }

  static Future<String?> getInstallId() {
    return _channel.invokeMethod<String>('getInstallId');
  }

  static Future<bool> isInitialized() async {
    final initialized = await _channel.invokeMethod<bool>('isInitialized');
    return initialized ?? false;
  }

  static Future<void> setLogLevel(AlignappsLogLevel level) {
    return _channel.invokeMethod<void>(
      'setLogLevel',
      <String, Object?>{'level': level.name.toUpperCase()},
    );
  }
}
