import 'package:alignapps_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the AlignApps example controls', (tester) async {
    await tester.pumpWidget(const DemoApp());

    expect(find.text('AlignApps Example'), findsOneWidget);
    expect(find.text('Initialize'), findsOneWidget);
    expect(find.text('Track Event'), findsOneWidget);
    expect(find.text('Track Registration'), findsOneWidget);
  });
}
