import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_central/main.dart';
import 'package:flutter_central/src/ble_central_controller.dart';

void main() {
  testWidgets('shows BLE central title', (WidgetTester tester) async {
    await tester.pumpWidget(
      FlutterCentralApp(
        controllerFactory: () => BleCentralController(enableBluetooth: false),
      ),
    );

    expect(find.text('Flutter macOS BLE Central'), findsOneWidget);
    expect(find.text('Target service FFF0, name MacBLE-Demo'), findsOneWidget);
    expect(find.text('Pair code'), findsOneWidget);
    expect(find.text('Quiet'), findsOneWidget);
    expect(find.text('Burst'), findsOneWidget);
  });
}
