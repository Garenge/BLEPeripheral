# MacCentralOC BLE Central

Pure macOS Objective-C app that scans for `MacBLE-Demo`, connects to service `FFF0`, and exercises characteristic `FFF1`.

## Open

`MacCentralOC.xcodeproj` in this folder.

## Run

1. Start `../MacPeripheralOC/BLEPeripheral.xcodeproj` first and wait for advertising.
2. Run scheme **MacCentralOC** on **My Mac**.
3. Allow Bluetooth permission.
4. Click **Scan**, select `MacBLE-Demo`, click **Connect**.
5. The app auto-enables Notify, sends Pair code `135790`, then requests `getInfo` capability discovery.
6. Use **Pair**, **Ping**, **Info**, **Echo**, **Telemetry**, **Command**, the event-rule segmented control, **Raw**, **Read**, and **Notify On/Off** to observe the GATT lifecycle.
7. You can also type `rule:quiet`, `rule:burst`, or `rule:normal` in the payload field and click **Command** to switch event association rules.

## What This Project Teaches

- `CBCentralManager` state changes and scanning
- `didDiscoverPeripheral` advertisement filtering
- `connectPeripheral` / `cancelPeripheralConnection`
- `discoverServices` and `discoverCharacteristics`
- `readValueForCharacteristic`
- `writeValue:forCharacteristic:type:`
- `setNotifyValue` and notification callbacks
- Session token capture from JSON `paired` responses
- Capability discovery from JSON `info` responses
- Event rule mode display and switching through `command setEventRule`
- Multi-event correlation: subscribe/write/read/reply/event logs

## Sources

- `MacCentralOC/AppDelegate.m` — simple macOS UI and button actions
- `MacCentralOC/BLECentralController.m` — CoreBluetooth Central flow

## BLE Profile

- Peripheral name: `MacBLE-Demo`
- Service: `0000FFF0-0000-1000-8000-00805F9B34FB`
- Characteristic: `0000FFF1-0000-1000-8000-00805F9B34FB`
- Protocol rule: Pair with `135790`, then include token for `echo`, `telemetry`, and `command`
- Capability rule: `getInfo` is open and returns supported operations, commands, event rules, security, and transport hints
- Event rule: `setEventRule` switches `normal`, `quiet`, or `burst` per Central session
- Raw rule: write any non-protocol payload, receive `00 AA` + original payload by notify or read
