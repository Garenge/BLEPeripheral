# FlutterCentral BLE Central

Flutter macOS app that uses `flutter_blue_plus` to scan, connect, pair, and exercise the `MacBLE-Demo` peripheral.

## Run

```bash
flutter run -d macos
```

Start `../MacPeripheralOC/BLEPeripheral.xcodeproj` first, then allow Bluetooth permission in the Flutter app.

After connecting, the app auto-enables Notify, sends Pair code `135790`, and requests `getInfo` capability discovery. Use **Pair**, **Ping**, **Info**, **Echo**, **Telemetry**, **Command**, the event-rule segmented control, **Raw**, **Read**, and **Notify On/Off** to compare JSON protocol traffic with legacy raw echo traffic.

## What This Project Teaches

- `FlutterBluePlus.adapterState`
- `FlutterBluePlus.startScan` with service `FFF0`
- Scanner match metadata for RSSI, service/name hit reason, last-seen time, and advertisement payload counts
- `BluetoothDevice.connect`
- `discoverServices`
- `BluetoothCharacteristic.read`
- `BluetoothCharacteristic.write`
- `BluetoothCharacteristic.setNotifyValue`
- `onValueReceived` for notify/read data
- JSON envelope encoding/decoding in Dart
- Session token capture from `paired` responses
- Capability summary capture from `info` responses
- Event rule mode display and switching through `command setEventRule`
- MTU chunk reassembly for oversized Notify replies/events

## Sources

- `lib/main.dart` — macOS learning UI
- `lib/src/ble_central_controller.dart` — BLE Central flow and log parsing
- `macos/Runner/Info.plist` — Bluetooth permission strings
- `macos/Runner/*.entitlements` — Bluetooth sandbox entitlement

## BLE Profile

- Peripheral name: `MacBLE-Demo`
- Service: `0000FFF0-0000-1000-8000-00805F9B34FB`
- Characteristic: `0000FFF1-0000-1000-8000-00805F9B34FB`
- Protocol rule: Pair with `135790`, then include token for `echo`, `telemetry`, and `command`
- Capability rule: `getInfo` is open and returns supported operations, commands, event rules, security, and transport hints
- Event rule: `setEventRule` switches `normal`, `quiet`, or `burst` per Central session
- Chunk rule: oversized Notify payloads arrive as `op=chunk`; the app logs progress, reassembles, then parses the original message
- Raw rule: write any non-protocol payload, receive `00 AA` + original payload by notify or read
