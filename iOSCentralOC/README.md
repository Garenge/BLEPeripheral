# iOSCentralOC BLE Central

iPhone app that scans for service `FFF0`, connects to `MacBLE-Demo`, and sends JSON protocol commands.

## Open

`BLECentral.xcodeproj` in this folder.

## Sources

- `BLECentral/` — UI and `BLECentralController`
- `../Shared/BLEProtocol/` — JSON codec (`BLEProtocolMessage`, constants; no `BLEProtocolHandler` on iOS)

## Run

Scheme **BLECentral** → physical **iPhone** → configure signing → Run.

Start the Mac peripheral first. See [../README.md](../README.md) for end-to-end steps.

Protocol details: [../ble_protocol.md](../ble_protocol.md)
