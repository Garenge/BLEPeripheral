# MacCentralOC BLE Central

Pure macOS Objective-C app that scans for `MacBLE-Demo`, connects to service `FFF0`, and exercises characteristic `FFF1`.

## Open

`MacCentralOC.xcodeproj` in this folder.

## Run

1. Start `../MacPeripheralOC/BLEPeripheral.xcodeproj` first and wait for advertising.
2. Run scheme **MacCentralOC** on **My Mac**.
3. Allow Bluetooth permission.
4. Click **Scan**, select `MacBLE-Demo`, click **Connect**.
5. Use **Write**, **Read**, and **Notify On/Off** to observe the GATT lifecycle.

## What This Project Teaches

- `CBCentralManager` state changes and scanning
- `didDiscoverPeripheral` advertisement filtering
- `connectPeripheral` / `cancelPeripheralConnection`
- `discoverServices` and `discoverCharacteristics`
- `readValueForCharacteristic`
- `writeValue:forCharacteristic:type:`
- `setNotifyValue` and notification callbacks

## Sources

- `MacCentralOC/AppDelegate.m` — simple macOS UI and button actions
- `MacCentralOC/BLECentralController.m` — CoreBluetooth Central flow

## BLE Profile

- Peripheral name: `MacBLE-Demo`
- Service: `0000FFF0-0000-1000-8000-00805F9B34FB`
- Characteristic: `0000FFF1-0000-1000-8000-00805F9B34FB`
- Echo rule: write any payload, receive `00 AA` + original payload by notify or read
