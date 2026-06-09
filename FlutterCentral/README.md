# FlutterCentral BLE Central

Flutter Android/iOS/macOS app that uses `flutter_blue_plus` to scan, connect, pair, and exercise the `MacBLE-Demo` peripheral.

## Run

```bash
flutter run -d android
flutter run -d ios
flutter run -d macos
```

Start `../MacPeripheralOC/BLEPeripheral.xcodeproj` first, then allow Bluetooth permission in the Flutter app.

After connecting, the app auto-enables Notify, sends Pair code `135790`, and requests `getInfo` capability discovery. Use **Run Demo** to queue Notify On, Pair, Info, Ping, long Echo, Telemetry, Burst/Normal rules, Sample/Identify commands, Raw, and Read; it runs one guarded flow at a time and cancels queued steps on disconnect. Use **Pair**, **Ping**, **Info**, **Echo**, **Telemetry**, **Command**, the event-rule segmented control, **Raw**, **Read**, and **Notify On/Off** to compare individual JSON protocol traffic with legacy raw echo traffic.

## Tutorial

See [flutter_ble_connection_and_transfer.md](flutter_ble_connection_and_transfer.md) for the Flutter BLE dependency, Android/iOS/macOS permissions, scan/connect/read/write/notify flow, and project protocol notes.

## Protocol

See [ble_protocol_spec.md](ble_protocol_spec.md) for the MacBLE-Demo GATT profile, JSON envelope, operations, commands, events, chunking, and legacy raw echo rules.

## Roadmap

See [mobile_ble_product_todo.md](mobile_ble_product_todo.md) for Android/iOS joint debugging, mobile UI adaptation, protocol documentation, and productization todos.

## Joint Debugging

See [mobile_ble_joint_debugging.md](mobile_ble_joint_debugging.md) for the Android/iOS real-device BLE acceptance flow, verification matrix, and log record template.

## Sources

- `lib/main.dart` — app bootstrap and theme entry
- `lib/src/ble_central_page.dart` — Android/iOS/macOS mobile-first BLE UI
- `lib/src/ble_central_controller.dart` — BLE Central flow and log parsing
- `android/app/src/main/AndroidManifest.xml` — Android Bluetooth permissions
- `ios/Runner/Info.plist` — iOS Bluetooth permission strings
- `macos/Runner/Info.plist` — Bluetooth permission strings
- `macos/Runner/*.entitlements` — Bluetooth sandbox entitlement
