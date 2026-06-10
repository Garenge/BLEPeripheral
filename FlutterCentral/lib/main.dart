import 'package:flutter/material.dart';

import 'src/ble_central_page.dart';

void main() {
  runApp(const FlutterCentralApp());
}

class FlutterCentralApp extends StatelessWidget {
  const FlutterCentralApp({super.key, this.controllerFactory});

  final BleCentralControllerFactory? controllerFactory;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter BLE Central',
      themeMode: ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        useMaterial3: true,
      ),
      home: BleCentralPage(controllerFactory: controllerFactory),
    );
  }
}
