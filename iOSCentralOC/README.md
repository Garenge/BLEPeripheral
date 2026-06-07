# iOSCentralOC BLE Central

iPhone app that scans for service `FFF0`, connects to `MacBLE-Demo`, and sends session-aware JSON protocol commands.

## Open

`BLECentral.xcodeproj` in this folder.

## Sources

- `BLECentral/` — UI and `BLECentralController`
- `../Shared/BLEProtocol/` — JSON codec (`BLEProtocolMessage`, constants; no `BLEProtocolHandler` on iOS)

## Run

Scheme **BLECentral** → physical **iPhone** → configure signing → Run.

Start the Mac peripheral first. Tap **Scan**, select `MacBLE-Demo`, and the app auto-enables Notify plus Pair code `135790`. Use **Pair**, **Ping**, **Info**, **Echo**, **Telemetry**, **Command**, **Raw**, **Read**, and **Notify On/Off** to compare protocol and legacy BLE behavior.

Protocol details: [../ble_protocol.md](../ble_protocol.md)
