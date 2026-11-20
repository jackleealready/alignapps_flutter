import 'package:alignapps_flutter/alignapps_flutter.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AlignApps Example',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  String _status = 'Not initialized';
  String? _installId;

  Future<void> _initialize() async {
    await _run(() async {
      final installId = await AlignappsFlutter.initialize(
        const AlignappsConfig(
          appKey: 'demo_app_key',
          serverUrl: 'https://attribution.example.com',
          logLevel: AlignappsLogLevel.debug,
          initialConsent: AlignappsConsent(
            analytics: true,
            advertisingId: false,
          ),
        ),
      );
      _installId = installId;
      _status = 'Initialized';
    });
  }

  Future<void> _track() {
    return _run(
      () => AlignappsFlutter.track('level_complete', <String, Object?>{
        'level': 12,
        'score': 90,
      }),
    );
  }

  Future<void> _trackRegistration() {
    return _run(
      () => AlignappsFlutter.track('register', <String, Object?>{
        'method': 'google',
      }),
    );
  }

  Future<void> _trackPurchase() {
    return _run(
      () => AlignappsFlutter.trackPurchase(
        orderId: 'order_1001',
        revenue: 4.99,
        currency: 'USD',
        properties: <String, Object?>{'product': 'starter_pack'},
      ),
    );
  }

  Future<void> _grantConsent() {
    return _run(
      () => AlignappsFlutter.setConsent(
        const AlignappsConsent(analytics: true, advertisingId: true),
      ),
    );
  }

  Future<void> _deepLink() {
    return _run(
      () => AlignappsFlutter.handleDeepLink(
        'https://link.example.com/demo?aa_click_id=demo_click',
      ),
    );
  }

  Future<void> _flush() {
    return _run(AlignappsFlutter.flush);
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _status = 'Success';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Error: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AlignApps Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(_status),
            Text('Install ID: ${_installId ?? '-'}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initialize,
              child: const Text('Initialize'),
            ),
            ElevatedButton(
              onPressed: _grantConsent,
              child: const Text('Grant Analytics + Advertising Consent'),
            ),
            ElevatedButton(onPressed: _track, child: const Text('Track Event')),
            ElevatedButton(
              onPressed: _trackRegistration,
              child: const Text('Track Registration'),
            ),
            ElevatedButton(
              onPressed: _trackPurchase,
              child: const Text('Track Purchase'),
            ),
            ElevatedButton(
              onPressed: _deepLink,
              child: const Text('Handle Deep Link'),
            ),
            ElevatedButton(onPressed: _flush, child: const Text('Flush')),
          ],
        ),
      ),
    );
  }
}
