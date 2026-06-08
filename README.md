# BLEPeripheral (monorepo)

BLE learning monorepo: one macOS BLE Peripheral, plus Central clients in Objective-C, iOS Objective-C, and Flutter macOS.

## Repository Layout

```
BLEPeripheral/                 # repo root
├── README.md                  # this file
├── ble_protocol.md            # JSON protocol v1
├── Shared/
│   ├── BLEProtocol/           # shared Objective-C sources
│   └── BLEProtocolTests/      # lightweight protocol smoke tests
├── MacPeripheralOC/
│   ├── BLEPeripheral.xcodeproj
│   └── BLEPeripheral/         # macOS Objective-C Peripheral app sources
├── MacCentralOC/
│   ├── MacCentralOC.xcodeproj
│   └── MacCentralOC/          # macOS Objective-C Central app sources
├── FlutterCentral/
│   ├── pubspec.yaml
│   ├── lib/                   # Flutter macOS Central app sources
│   └── macos/
└── iOSCentralOC/
    ├── BLECentral.xcodeproj
    └── BLECentral/            # iOS Objective-C Central app sources
```

| Open in Xcode | Path | Run on |
|---------------|------|--------|
| Mac Objective-C peripheral | `MacPeripheralOC/BLEPeripheral.xcodeproj` | My Mac |
| Mac Objective-C central | `MacCentralOC/MacCentralOC.xcodeproj` | My Mac |
| iPhone Objective-C central | `iOSCentralOC/BLECentral.xcodeproj` | Physical iPhone (recommended) |

| Open in Flutter | Path | Run on |
|-----------------|------|--------|
| Flutter macOS central | `FlutterCentral/` | My Mac |

## Current Status

Implemented:

- macOS Objective-C peripheral app with session tracking per Central
- macOS Objective-C central app for scanning, pairing, reading, writing, notify, telemetry, and commands
- iOS Objective-C central app with the same protocol controls
- Flutter macOS central app using `flutter_blue_plus` with the same protocol controls
- **FFF1 简单回显**：`00 AA` + 对方原始内容（见 [ble_simple_echo.md](ble_simple_echo.md)）
- Shared JSON protocol v1 in `Shared/BLEProtocol/`
- GATT service `FFF0`, characteristic `FFF1` (`read` / `write` / `notify`)
- Protocol: `pair`, `ping`, `getInfo`, `echo`, `telemetry`, `command`, server `event`; legacy raw writes
- Notify queue with MTU-aware `op=chunk` splitting and bounded automatic reassembly in Mac/iOS/Flutter Central clients
- Recorded BLE payload fixtures shared by Objective-C and Flutter protocol tests

See [ble_protocol.md](ble_protocol.md) for message format.

Default demo pair code: `135790`.

## Quick Start

### 1. Mac Objective-C peripheral

```bash
open MacPeripheralOC/BLEPeripheral.xcodeproj
```

Run **BLEPeripheral** on **My Mac** → allow Bluetooth → wait for `Advertising started`.

### 2. Pick a Central client

Objective-C macOS:

```bash
open MacCentralOC/MacCentralOC.xcodeproj
```

Run **MacCentralOC** on **My Mac** → allow Bluetooth → **Scan** → select `MacBLE-Demo` → **Connect**. The app auto-enables Notify and auto-pairs with code `135790`; then use **Run Demo** to exercise the full guarded flow, or use **Ping**, **Info**, **Echo**, **Telemetry**, **Command**, **Raw**, **Read**, and **Notify On/Off** manually. Type `rule:quiet`, `rule:burst`, or `rule:normal` in the payload field and press **Command** to switch event rules.

Flutter macOS:

```bash
cd FlutterCentral
flutter run -d macos
```

Allow Bluetooth → **Scan** → connect `MacBLE-Demo`. The app auto-enables Notify and auto-pairs; then use **Run Demo** to exercise the full guarded flow, or use **Pair**, **Ping**, **Info**, **Echo**, **Telemetry**, **Command**, **Rule Normal/Quiet/Burst**, **Raw**, **Read**, and **Notify On/Off** manually.

iPhone Objective-C:

```bash
open iOSCentralOC/BLECentral.xcodeproj
```

Select your iPhone, set **Signing Team**, run **BLECentral** → **Scan** → connect `MacBLE-Demo`. The app auto-enables Notify and auto-pairs; then use **Run Demo** to exercise the full guarded flow, or use **Pair**, **Ping**, **Info**, **Echo**, **Telemetry**, **Command**, **Raw**, **Read**, and **Notify On/Off** manually. Type `rule:quiet`, `rule:burst`, or `rule:normal` in the text field and tap **Command** to switch event rules.

### Terminal verification

```bash
# Fast protocol + Flutter checks
scripts/verify_ble_suite.sh

# Full local build check for all first-party apps
scripts/verify_ble_suite.sh --xcode
```

`--xcode` stores verbose build logs under `${TMPDIR:-/tmp}/ble_suite_verify_logs` and prints them only when a build step fails.

## BLE Profile

- Name: `MacBLE-Demo`
- Service: `0000FFF0-0000-1000-8000-00805F9B34FB`
- Characteristic: `0000FFF1-0000-1000-8000-00805F9B34FB`

## Per-Project Docs

- [MacPeripheralOC/README.md](MacPeripheralOC/README.md) — macOS Objective-C peripheral notes
- [MacCentralOC/README.md](MacCentralOC/README.md) — macOS Objective-C central notes
- [FlutterCentral/README.md](FlutterCentral/README.md) — Flutter macOS central notes
- [iOSCentralOC/README.md](iOSCentralOC/README.md) — iPhone Objective-C central notes
- [Shared/BLEProtocolTests/README.md](Shared/BLEProtocolTests/README.md) — Objective-C protocol smoke tests

## Learning Path

1. Start `MacPeripheralOC/BLEPeripheral` and watch advertising + GATT logs.
2. Run `MacCentralOC` to learn CoreBluetooth Central APIs directly: `CBCentralManager`, `CBPeripheral`, `CBService`, `CBCharacteristic`.
3. Run `FlutterCentral` to compare the same BLE flow through a cross-platform plugin.
4. Run `iOSCentralOC/BLECentral` on a phone to compare real-device Central behavior against macOS Central behavior.

Core Central sequence:

`scanForPeripherals` → `connectPeripheral` → `discoverServices` → `discoverCharacteristics` → `setNotifyValue` / `readValue` / `writeValue`

First-party protocol sequence:

`scan` → `connect` → `discover FFF0/FFF1` → `notify on` → `pair(code=135790)` + `getInfo` → `token` + capabilities → protected `echo` / `telemetry` / `command` → queued notify replies / `event` notifications → `chunk` reassembly when needed

Demo commands: `identify`, `sample`, `resetCounters`, `setEventRule`.

## Operation Matrix

| UI action | BLE transport | Requires token | Expected result |
|-----------|---------------|----------------|-----------------|
| Pair | Write + Notify/Read | No | `paired` response with session token, then `event.type=paired` |
| Ping | Write + Notify/Read | No | `pong` response for diagnostics |
| Info | Write + Notify/Read | No | `info` response with GATT/profile metadata, operation groups, command catalog, event rules, and transport/security hints |
| Echo | Write + Notify/Read | Yes | `echo` response with same text |
| Telemetry | Write + Notify/Read | Yes | Session read/write/notify/event counters |
| Command `identify` | Write + Notify | Yes | `commandResult`, then `event.type=command.identify` |
| Command `sample` | Write + Notify | Yes | `commandResult`, then simulated sample telemetry event |
| Command `resetCounters` | Write + Notify | Yes | `commandResult`, then counter reset event |
| Command `setEventRule` | Write + Notify | Yes | Switches `normal` / `quiet` / `burst`; pushes `event.ruleChanged` |
| Raw | Write + Notify/Read | No | Legacy `00 AA` + original bytes |
| Chunk | Notify | No | Automatic transport wrapper for oversized replies/events; clients reassemble then parse original payload |
| Run Demo | Write + Notify + Read | Mixed | Queues Notify On, Pair, Info, Ping, long Echo, Telemetry, Burst rule, Sample command, Normal rule, Identify command, Raw, and Read; runs one flow at a time and cancels queued steps on disconnect |

## Next Work

- Configurable profile + persistence
- Real-device BLE integration script/checklist for Mac peripheral + iPhone/Flutter clients
