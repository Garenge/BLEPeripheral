# BLEPeripheral

Minimal macOS BLE Peripheral simulator written in Objective-C.

This project is currently a small runnable demo. The goal is to let a Mac act as a BLE Peripheral and let an iPhone act as the Central for scanning, connecting, reading, writing, and receiving notifications.

## Current Status

Implemented:

- macOS Objective-C Cocoa app
- CoreBluetooth `CBPeripheralManager`
- BLE advertising from the Mac
- One primary GATT service
- One characteristic that supports `read`, `write`, `writeWithoutResponse`, and `notify`
- Basic app window with runtime logs
- Periodic notify every 2 seconds while a Central is subscribed
- Echo notify after iPhone writes a value, when subscribed

Not implemented yet:

- Custom UI controls for changing service UUID, characteristic UUID, device name, and notify interval
- Multiple services or multiple characteristics
- Persistent configuration
- Structured request/response protocol
- iPhone companion Central app
- Automated tests
- Packaging, notarization, or release build setup

## BLE Profile

Current demo values:

- Peripheral name: `MacBLE-Demo`
- Service UUID: `0000FFF0-0000-1000-8000-00805F9B34FB`
- Characteristic UUID: `0000FFF1-0000-1000-8000-00805F9B34FB`
- Characteristic properties: `read`, `write`, `writeWithoutResponse`, `notify`
- Initial read value: `Hello from macOS BLE Peripheral`
- Notify behavior: sends text payload like `notify #1 from Mac at 10:30:00`

Main BLE code is in:

- `BLEPeripheral/BLEPeripheralController.h`
- `BLEPeripheral/BLEPeripheralController.m`

Main app UI code is in:

- `BLEPeripheral/AppDelegate.h`
- `BLEPeripheral/AppDelegate.m`

## Run

Open `BLEPeripheral.xcodeproj` in Xcode and run the `BLEPeripheral` scheme on My Mac.

Or build from Terminal:

```bash
xcodebuild -project BLEPeripheral.xcodeproj -scheme BLEPeripheral -configuration Debug build
```

On first launch, macOS may ask for Bluetooth permission. Allow it, or enable it later in:

`System Settings > Privacy & Security > Bluetooth`

Also make sure Bluetooth is enabled on both the Mac and the iPhone.

## iPhone Manual Test

Use an iPhone Central app such as LightBlue or nRF Connect:

1. Run the Mac app.
2. Wait for the Mac app log to show `Advertising started`.
3. On iPhone, scan for `MacBLE-Demo`.
4. Connect to `MacBLE-Demo`.
5. Open service `FFF0`.
6. Read characteristic `FFF1`.
7. Write UTF-8 text to `FFF1`.
8. Subscribe to notifications on `FFF1`.
9. Confirm the iPhone receives periodic notify payloads.
10. Confirm the Mac app logs reads, writes, subscription changes, and notification sends.

Expected behavior:

- Read returns the current stored value.
- Write replaces the current stored value.
- If notify is subscribed, write also tries to echo the written value back to the iPhone.
- Periodic notify continues every 2 seconds while subscribed.

## Next Development Work

Recommended next steps, roughly in order:

1. Add basic controls to the Mac UI
   - Start advertising
   - Stop advertising
   - Clear logs
   - Send manual notify
   - Edit notify payload

2. Make BLE profile configurable
   - Peripheral name
   - Service UUID
   - Characteristic UUID
   - Initial read value
   - Notify interval

3. Improve notify handling
   - Store pending notify data when `updateValue` returns `NO`
   - Retry pending data from `peripheralManagerIsReadyToUpdateSubscribers:`
   - Respect `central.maximumUpdateValueLength`
   - Split large payloads if needed

4. Add multiple characteristics
   - Read-only characteristic
   - Write-only characteristic
   - Notify-only characteristic
   - Combined read/write/notify characteristic

5. Add a simple protocol layer
   - Define message format, for example JSON or binary TLV
   - Log decoded requests
   - Generate deterministic responses
   - Add malformed payload handling

6. Add persistence
   - Save profile settings in `NSUserDefaults`
   - Restore last used service and characteristic setup on launch
   - Add reset-to-demo-defaults action

7. Add iPhone Central sample app
   - Scan by service UUID
   - Connect to Mac
   - Discover service and characteristic
   - Read, write, subscribe, and display notifications
   - This can be a separate Objective-C or Swift iOS target

8. Add diagnostics
   - Show Bluetooth authorization state
   - Show advertising state
   - Show connected/subscribed Central count
   - Show last read/write/notify payload as text and hex
   - Export logs to a file

9. Add tests where practical
   - Unit-test payload encoding and decoding
   - Unit-test configuration persistence
   - Keep CoreBluetooth behavior mostly manual-tested because it depends on real hardware and system Bluetooth state

10. Prepare for distribution
    - Choose final bundle identifier
    - Add app icon
    - Decide whether sandboxing is needed
    - Configure signing team
    - Test on another Mac
    - Consider notarization if sharing outside local development

## Useful Notes

- macOS BLE Peripheral support depends on Mac hardware, Bluetooth state, app permission, and system policy.
- Advertising may fail if Bluetooth is off, permission is denied, or another state transition is in progress.
- iOS scanner apps may show the full 128-bit UUID instead of the short `FFF0` / `FFF1` form.
- Some iPhone apps cache GATT services. If the UUIDs or characteristic properties change during development, disconnect, forget/clear cache if the app supports it, or restart Bluetooth/app.
- Keep the app open and foregrounded while testing until background behavior is intentionally designed.

## Known Limitations

- The current app uses one characteristic for everything.
- Notify payloads are simple UTF-8 strings.
- There is no backpressure queue yet for notify sends.
- There is no MTU-aware payload splitting yet.
- There is no polished UI yet, only a log window.
- There is no iPhone sample app in this repository yet.

## Quick Resume Checklist

When returning to this project:

1. Build the current demo with `xcodebuild`.
2. Run the Mac app from Xcode.
3. Confirm the log reaches `Advertising started`.
4. Scan from iPhone with LightBlue or nRF Connect.
5. Verify read, write, and notify.
6. Pick the next task from `Next Development Work`.
