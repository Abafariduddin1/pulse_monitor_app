import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_monitor_app/main.dart';

void main() {
  testWidgets('PulseApp renders successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const PulseApp());
    expect(find.byType(PulseApp), findsOneWidget);
  });
}