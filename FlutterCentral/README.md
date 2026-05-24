# FlutterCentral BLE Central

Flutter macOS app that uses `flutter_blue_plus` to scan and connect to the `MacBLE-Demo` peripheral.

## Run

```bash
flutter run -d macos
```

Start `../MacPeripheralOC/BLEPeripheral.xcodeproj` first, then allow Bluetooth permission in the Flutter app.

## What This Project Teaches

- `FlutterBluePlus.adapterState`
- `FlutterBluePlus.startScan` with service `FFF0`
- `BluetoothDevice.connect`
- `discoverServices`
- `BluetoothCharacteristic.read`
- `BluetoothCharacteristic.write`
- `BluetoothCharacteristic.setNotifyValue`
- `onValueReceived` for notify/read data

## Sources

- `lib/main.dart` — macOS learning UI
- `lib/src/ble_central_controller.dart` — BLE Central flow and log parsing
- `macos/Runner/Info.plist` — Bluetooth permission strings
- `macos/Runner/*.entitlements` — Bluetooth sandbox entitlement

## BLE Profile

- Peripheral name: `MacBLE-Demo`
- Service: `0000FFF0-0000-1000-8000-00805F9B34FB`
- Characteristic: `0000FFF1-0000-1000-8000-00805F9B34FB`
- Echo rule: write any payload, receive `00 AA` + original payload by notify or read
