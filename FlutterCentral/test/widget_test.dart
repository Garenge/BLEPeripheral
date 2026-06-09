import 'package:flutter/material.dart';
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

    expect(find.text('Flutter BLE Central'), findsOneWidget);
    expect(find.text('Target service FFF0, name MacBLE-Demo'), findsOneWidget);

    await tester.tap(find.text('Operate'));
    await tester.pumpAndSettle();

    expect(find.text('Pair code'), findsOneWidget);
    expect(find.text('Run Demo'), findsOneWidget);
    expect(find.text('Info'), findsOneWidget);
    expect(find.text('Echo'), findsOneWidget);
  });

  testWidgets('mobile layout keeps logs in a dedicated tab', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      FlutterCentralApp(
        controllerFactory: () => BleCentralController(enableBluetooth: false),
      ),
    );

    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Operate'), findsOneWidget);
    expect(find.text('Logs'), findsOneWidget);

    await tester.tap(find.text('Logs'));
    await tester.pumpAndSettle();

    expect(find.text('Logs'), findsWidgets);
    expect(find.text('1 event(s)'), findsOneWidget);
    expect(find.byTooltip('Copy logs'), findsOneWidget);
    expect(find.byTooltip('Clear logs'), findsOneWidget);
    expect(
      find.textContaining('Bluetooth disabled for widget test'),
      findsOneWidget,
    );
  });
}
