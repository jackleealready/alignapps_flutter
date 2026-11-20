import 'package:alignapps_flutter/alignapps_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.alignapps/flutter');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('default consent enables analytics and advertising id', () {
    const consent = AlignappsConsent();

    expect(consent.analytics, isTrue);
    expect(consent.advertisingId, isTrue);
  });

  test('initialize forwards the complete configuration', () async {
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return 'install-123';
    });

    const config = AlignappsConfig(
      appKey: 'app_key',
      serverUrl: 'https://attribution.example.com',
      logLevel: AlignappsLogLevel.debug,
      initialConsent: AlignappsConsent(
        analytics: true,
        advertisingId: false,
      ),
    );

    final installId = await AlignappsFlutter.initialize(config);

    expect(installId, 'install-123');
    expect(captured?.method, 'initialize');
    expect(captured?.arguments['appKey'], 'app_key');
    expect(captured?.arguments['logLevel'], 'DEBUG');
  });

  test('track forwards event properties', () async {
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return null;
    });

    await AlignappsFlutter.track('level_complete', <String, Object?>{
      'level': 12,
      'score': 90,
    });

    expect(captured?.method, 'track');
    expect(captured?.arguments['eventName'], 'level_complete');
    expect(captured?.arguments['properties']['level'], 12);
  });

  test('getConsent parses native response', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return <String, Object?>{
        'analytics': true,
        'advertisingId': true,
      };
    });

    final consent = await AlignappsFlutter.getConsent();

    expect(consent.analytics, isTrue);
    expect(consent.advertisingId, isTrue);
  });
}
