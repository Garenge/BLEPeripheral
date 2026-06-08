# iOSCentralOC BLE Central

iPhone app that scans for service `FFF0`, connects to `MacBLE-Demo`, and sends session-aware JSON protocol commands.

## Open

`BLECentral.xcodeproj` in this folder.

## Sources

- `BLECentral/` — UI and `BLECentralController`
- `../Shared/BLEProtocol/` — JSON codec (`BLEProtocolMessage`, constants; no `BLEProtocolHandler` on iOS)

## Run

Scheme **BLECentral** → physical **iPhone** → configure signing → Run.

Start the Mac peripheral first. Tap **Scan**, select `MacBLE-Demo`, and the app auto-enables Notify, Pair code `135790`, and `getInfo` capability discovery. Use **Run Demo** to queue Notify On, Pair, Info, Ping, long Echo, Telemetry, Burst/Normal rules, Sample/Identify commands, Raw, and Read; it runs one guarded flow at a time and cancels queued steps on disconnect. Use **Pair**, **Ping**, **Info**, **Echo**, **Telemetry**, **Command**, the event-rule segmented control, **Raw**, **Read**, and **Notify On/Off** to compare individual protocol and legacy BLE behavior.

You can also type `rule:quiet`, `rule:burst`, or `rule:normal` in the text field and tap **Command** to switch event association rules.

`info` responses log a `CAP` summary for supported operations, commands, event rules, security, and transport hints.

The scanner list shows RSSI, service/name hit reason, and last-seen time for each discovered peripheral.

Oversized Notify replies/events arrive as JSON `op=chunk`; the app logs chunk progress, caps incomplete reassembly to 8 streams / 256 parts per stream / 64 KiB total, reassembles by stream/index, then parses the original protocol or legacy payload.

Protocol details: [../ble_protocol.md](../ble_protocol.md)
