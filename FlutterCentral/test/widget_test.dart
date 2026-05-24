import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_central/main.dart';

void main() {
  testWidgets('shows BLE central title', (WidgetTester tester) async {
    await tester.pumpWidget(const FlutterCentralApp());

    expect(find.text('Flutter macOS BLE Central'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
  });
}
