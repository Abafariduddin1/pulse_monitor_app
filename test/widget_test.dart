import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_monitor_app/main.dart';

void main() {
  testWidgets('Pulse app loads correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SecurePulseApp());

    // Verify that the title appears
    expect(find.text('Pulse Monitor'), findsOneWidget);
  });
}