import 'package:flutter_test/flutter_test.dart';
import 'package:secure_pulse/main.dart';

void main() {
  testWidgets('App starts without crashing', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SecurePulseApp());

    // Verify that the title appears
    expect(find.text('Secure Pulse'), findsWidgets);
    
    // Verify that the initial placeholder text appears
    expect(find.text('--'), findsOneWidget);
  });
}