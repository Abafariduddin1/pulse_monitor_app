import 'package:flutter_test/flutter_test.dart';
import 'package:secure_pulse/main.dart';

void main() {
  testWidgets('App starts without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const SecurePulseApp());
    expect(find.text('Connect to PulseShield'), findsWidgets);
  });
}