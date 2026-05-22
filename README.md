# BLEPeripheral (monorepo)

Two separate Xcode projects for macOS BLE Peripheral and iPhone BLE Central, plus a shared JSON protocol.

## Repository Layout

```
BLEPeripheral/                 # repo root
├── README.md                  # this file
├── ble_protocol.md            # JSON protocol v1
├── Shared/
│   └── BLEProtocol/           # shared Objective-C sources
├── Mac/
│   ├── BLEPeripheral.xcodeproj
│   └── BLEPeripheral/         # macOS app sources
└── iOS/
    ├── BLECentral.xcodeproj
    └── BLECentral/            # iOS app sources
```

| Open in Xcode | Path | Run on |
|---------------|------|--------|
| Mac peripheral | `Mac/BLEPeripheral.xcodeproj` | My Mac |
| iPhone central | `iOS/BLECentral.xcodeproj` | Physical iPhone (recommended) |

## Current Status

Implemented:

- macOS peripheral app + iOS central app (Objective-C)
- **FFF1 简单回显**：`00 AA` + 对方原始内容（见 [ble_simple_echo.md](ble_simple_echo.md)）
- Shared JSON protocol v1 in `Shared/BLEProtocol/`（iOS 示例 App 仍可用，Mac 已改为回显模式）
- GATT service `FFF0`, characteristic `FFF1` (`read` / `write` / `notify`)
- Protocol: `ping`, `echo`, `getInfo`, server `tick`; legacy raw UTF-8 writes

See [ble_protocol.md](ble_protocol.md) for message format.

## Quick Start

### 1. Mac peripheral

```bash
open Mac/BLEPeripheral.xcodeproj
```

Run **BLEPeripheral** on **My Mac** → allow Bluetooth → wait for `Advertising started`.

### 2. iPhone central

```bash
open iOS/BLECentral.xcodeproj
```

Select your iPhone, set **Signing Team**, run **BLECentral** → **Scan** → connect `MacBLE-Demo` → **Notify On** → **Ping**.

### Terminal build

```bash
# macOS
xcodebuild -project Mac/BLEPeripheral.xcodeproj -scheme BLEPeripheral -configuration Debug build

# iOS
xcodebuild -project iOS/BLECentral.xcodeproj -scheme BLECentral -configuration Debug -sdk iphoneos build
```

## BLE Profile

- Name: `MacBLE-Demo`
- Service: `0000FFF0-0000-1000-8000-00805F9B34FB`
- Characteristic: `0000FFF1-0000-1000-8000-00805F9B34FB`

## Per-Project Docs

- [Mac/README.md](Mac/README.md) — peripheral-only notes
- [iOS/README.md](iOS/README.md) — central-only notes

## Next Work

- Mac UI controls (advertise start/stop, etc.)
- Configurable profile + persistence
- Notify queue / MTU splitting
- Unit tests for `Shared/BLEProtocol`
