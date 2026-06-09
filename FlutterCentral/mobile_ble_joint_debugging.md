# Mobile BLE Joint Debugging

本文用于 Android 真机、iPhone 真机和 macOS 辅助端对 `MacBLE-Demo` 做 BLE 联调验收。目标是把扫描、连接、配对、数据传输和异常记录变成可复现流程。

## 设备准备

需要同时准备：

- 运行 `../MacPeripheralOC/BLEPeripheral.xcodeproj` 的 Mac，作为 BLE Peripheral。
- 一台 Android 真机，作为 FlutterCentral Android Central。
- 一台 iPhone 真机，作为 FlutterCentral iOS Central。
- 当前 Mac 可作为 FlutterCentral macOS Central 辅助验证端。

Android 模拟器和 iOS 模拟器不作为 BLE 链路验收依据。模拟器可以用于 UI 编译和页面检查，但不能证明真实扫描、连接和 Notify 行为。

## 运行命令

先确认设备：

```bash
flutter devices
adb devices -l
xcrun xctrace list devices
```

分别运行移动端：

```bash
flutter run -d android
flutter run -d ios
```

macOS 辅助端：

```bash
flutter run -d macos
```

## 外设检查

启动 `../MacPeripheralOC/BLEPeripheral.xcodeproj` 后确认：

- Peripheral name: `MacBLE-Demo`
- Service UUID: `0000FFF0-0000-1000-8000-00805F9B34FB`
- Characteristic UUID: `0000FFF1-0000-1000-8000-00805F9B34FB`
- Characteristic properties: `read`, `write`, `writeWithoutResponse`, `notify`
- Pair code: `135790`

## 验收流程

每台移动设备都按同一流程执行：

1. 打开系统蓝牙。
2. 启动 FlutterCentral。
3. 允许蓝牙权限。
4. 在 `Connect` 页点击 `Scan`。
5. 确认列表出现 `MacBLE-Demo`，记录 RSSI、remoteId、命中原因。
6. 点击 `Connect`。
7. 确认状态变成 connected，发现 Service `FFF0` 和 Characteristic `FFF1`。
8. 确认 Notify 自动开启。
9. 确认自动发送 Pair code `135790` 并捕获 session token。
10. 确认自动执行 `getInfo`，并展示能力摘要。
11. 在 `Operate` 页分别执行 `Ping`、`Echo`、`Telemetry`、`Command`。
12. 展开 `Advanced`，执行 `Raw` 和 `Read`。
13. 执行 `Run Demo`，观察完整流程。
14. 在 `Logs` 页复制日志并保存到联调记录。

## 验收矩阵

| Item | Android | iOS | Notes |
| --- | --- | --- | --- |
| 权限弹窗正常出现并授权 |  |  | 记录系统版本和权限文案 |
| 扫描到 `MacBLE-Demo` |  |  | 记录扫描耗时和 RSSI |
| 连接成功 |  |  | 记录 remoteId 表现 |
| 发现 Service `FFF0` |  |  |  |
| 发现 Characteristic `FFF1` |  |  |  |
| Notify 开启成功 |  |  |  |
| Pair 成功并捕获 token |  |  |  |
| `getInfo` 成功 |  |  |  |
| `ping` / `pong` 成功 |  |  |  |
| `echo` 成功 |  |  |  |
| `telemetry` 成功 |  |  |  |
| `command identify` 成功 |  |  |  |
| `command sample` 成功 |  |  |  |
| `setEventRule normal/quiet/burst` 成功 |  |  |  |
| Raw echo 返回 `00 AA` 前缀 |  |  |  |
| oversized Notify chunk 可重组 |  |  |  |
| 断开后状态清理正常 |  |  |  |
| 重新扫描连接正常 |  |  |  |
| 移动端页面无溢出、无重叠 |  |  |  |
| 日志可读、可复制 |  |  |  |

## 日志记录格式

每轮联调记录以下信息：

```text
Date:
Flutter commit:
Peripheral app commit:
Android device / OS:
iPhone device / iOS:
Peripheral Mac / macOS:
Scan result:
Connection result:
Pair token captured:
Operations verified:
Chunk verified:
Raw echo verified:
UI notes:
Known differences:
Logs:
```

## 常见差异

- Android 12 及以上使用附近设备权限；Android 11 及以下可能仍要求定位权限参与 BLE 扫描。
- iOS 必须使用真机验证蓝牙链路；模拟器只能用于构建和 UI 检查。
- iOS 可能复用系统级外设标识，Android remoteId 表现依机型和系统版本不同。
- MTU 和 Notify 分片长度由系统协商，不能假设 Android/iOS 一致。
- 如果同一台 Mac 同时运行外设和 macOS Central，可能无法代表移动端真实链路，应以 Android/iPhone 真机为准。
