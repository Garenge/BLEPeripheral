# Flutter BLE Connection And Transfer

本文记录 `FlutterCentral` 如何作为 BLE Central 端扫描、连接 `MacBLE-Demo` 外设，并完成数据读写、Notify 订阅和 JSON 协议传输。

## 角色说明

本项目的 Flutter App 是 Central，也就是客户端：

- 扫描广播了目标 Service UUID 的 BLE Peripheral。
- 连接目标设备并发现 GATT Service / Characteristic。
- 对 Characteristic 执行 `read`、`write`、`setNotifyValue`。
- 监听 Notify/Read 回包并解析业务协议。

当前目标外设：

- Peripheral name: `MacBLE-Demo`
- Service UUID: `0000FFF0-0000-1000-8000-00805F9B34FB`
- Characteristic UUID: `0000FFF1-0000-1000-8000-00805F9B34FB`
- Pair code: `135790`

## 第三方库

项目使用了第三方库 `flutter_blue_plus`：

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_blue_plus: ^2.3.3
```

集成命令：

```bash
flutter pub add flutter_blue_plus
```

本项目已经在 `pubspec.yaml` 中集成，无需重复执行。`flutter_blue_plus` 是 BLE Central 能力库，负责适配 Android、iOS、macOS、Linux、Web 等平台的扫描、连接、GATT 发现、读写和 Notify。当前项目生成并验证了 Android、iOS 和 macOS 端。

## 平台配置

### Android

`flutter_blue_plus` 要求 Android `minSdk` 至少为 21。本项目使用 Flutter 模板的 `flutter.minSdkVersion`：

```kotlin
defaultConfig {
    minSdk = flutter.minSdkVersion
}
```

当前验证环境是 Flutter 3.41.4，`flutter.minSdkVersion` 为 24，已经满足 `flutter_blue_plus` 的最低要求。若后续切换到更老的 Flutter SDK，需要确认该值仍不低于 21。

Android 需要在 `android/app/src/main/AndroidManifest.xml` 声明 BLE 权限。本项目使用“不用于定位”的扫描方案：

```xml
<uses-feature
    android:name="android.hardware.bluetooth_le"
    android:required="false" />

<uses-permission
    android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

<uses-permission
    android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30" />
<uses-permission
    android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30" />
<uses-permission
    android:name="android.permission.ACCESS_FINE_LOCATION"
    android:maxSdkVersion="30" />
<uses-permission
    android:name="android.permission.ACCESS_COARSE_LOCATION"
    android:maxSdkVersion="28" />
```

注意点：

- Android 12 及以上使用 `BLUETOOTH_SCAN` 和 `BLUETOOTH_CONNECT`。
- `neverForLocation` 表示 BLE 扫描不用于推断位置，因此当前代码不需要给 `startScan` 传 `androidUsesFineLocation: true`。
- Android 11 及以下仍需要 legacy 蓝牙权限，部分系统还要求定位权限才能扫描 BLE。
- Android 真机需要开启蓝牙；如果扫描状态卡在 unauthorized，优先检查系统权限弹窗是否被拒绝。
- `android/build.gradle.kts` 中保留了 `https://storage.googleapis.com/download.flutter.io` Maven 仓库兜底，用于下载 Flutter Android engine artifacts，避免部分镜像缺失时 Android 构建失败。

### iOS

iOS 需要在 `ios/Runner/Info.plist` 声明蓝牙用途，否则系统可能拒绝授权或运行时崩溃：

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Scan and connect to the MacBLE-Demo peripheral for BLE learning.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Scan and connect to the MacBLE-Demo peripheral for BLE learning.</string>
```

注意点：

- iOS 的 BLE 扫描和连接需要真机验证，模拟器不能完成真实蓝牙链路测试。
- iOS 上第一次调用蓝牙 API 时会弹出系统权限弹窗。
- iOS 扫描建议带 `withServices`，本项目已经使用目标 Service UUID 过滤。

### macOS

macOS 需要两类配置：

`macos/Runner/Info.plist` 中声明蓝牙用途：

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Scan and connect to the MacBLE-Demo peripheral for BLE learning.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Scan and connect to the MacBLE-Demo peripheral for BLE learning.</string>
```

`macos/Runner/DebugProfile.entitlements` 和 `macos/Runner/Release.entitlements` 中打开蓝牙沙盒权限：

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
```

## 核心代码位置

- `lib/src/ble_central_controller.dart`: BLE 扫描、连接、读写、Notify 和日志状态。
- `lib/src/ble_protocol_codec.dart`: JSON 协议编码、解码、token 提取、chunk 解析。
- `lib/src/ble_chunk_reassembler.dart`: 大包 Notify 分片重组。
- `lib/main.dart`: App 启动入口和主题配置。
- `lib/src/ble_central_page.dart`: Android/iOS/macOS 移动端优先的 BLE 操作 UI。

## 扫描设备

项目在 `BleCentralController.startScan()` 中扫描目标 Service：

```dart
await FlutterBluePlus.startScan(
  withServices: [demoServiceUuid],
  timeout: const Duration(seconds: 12),
);
```

扫描结果来自：

```dart
FlutterBluePlus.onScanResults.listen(_handleScanResults);
```

项目会记录：

- 设备名。
- `remoteId`。
- RSSI。
- 命中原因：Service UUID、设备名或 Service filter。
- 广播中的 service/manufacturer/serviceData 数量。

## 连接设备

连接入口是 `BleCentralController.connect(String remoteId)`：

```dart
final device = BluetoothDevice.fromId(remoteId);
await device.connect(
  license: License.free,
  timeout: const Duration(seconds: 20),
  mtu: null,
);
```

连接成功后会监听连接状态：

```dart
final subscription = device.connectionState.listen((state) {
  if (state == BluetoothConnectionState.disconnected) {
    _clearGattState();
  }
});
device.cancelWhenDisconnected(subscription, delayed: true);
```

断开时项目会清理：

- 当前设备。
- 当前 Characteristic。
- Notify 状态。
- Pair token。
- 能力摘要。
- Chunk 重组缓存。

## 发现 GATT

连接后调用 `discoverServices()` 查找目标 Service 和 Characteristic：

```dart
final services = await device.discoverServices();
final service = services
    .where((item) => item.uuid == demoServiceUuid)
    .firstOrNull;

final characteristic = service.characteristics
    .where((item) => item.uuid == demoCharacteristicUuid)
    .firstOrNull;
```

找到目标 Characteristic 后，项目会自动执行：

1. 开启 Notify。
2. 读取一次当前值。
3. 发送 Pair code。
4. 请求 `getInfo` 能力发现。

## 开启 Notify

Notify 用于接收外设主动推送的数据：

```dart
_valueSubscription = characteristic.onValueReceived.listen((value) {
  _logIncoming(value, 'RX notify/read');
});

await characteristic.setNotifyValue(true);
```

在 `flutter_blue_plus` 中，`onValueReceived` 会收到 Notify 数据，也会收到部分平台上的 Read 回调数据，所以项目统一用 `_logIncoming` 解析入口处理。

## 读取数据

读取 Characteristic：

```dart
final value = await characteristic.read();
_logIncoming(value, 'RX read');
```

本项目中 `Read` 按钮会触发 `readValue()`，用于观察外设当前 Characteristic 值或 legacy raw echo 回包。

## 写入数据

原始文本写入：

```dart
final payload = utf8.encode(text);
await characteristic.write(payload, withoutResponse: false);
```

协议消息写入：

```dart
final payload = _protocolCodec.encodeRequest(
  operation: operation,
  messageId: 'flutter-$_protocolSequence',
  body: body,
  token: includeToken ? sessionToken : null,
);
await characteristic.write(payload, withoutResponse: false);
```

`withoutResponse: false` 表示使用带响应写入，便于学习和调试。如果后续要做高吞吐数据传输，可以评估外设是否支持 Write Without Response，并配合 MTU/分包策略优化。

## JSON 协议

本项目把业务请求编码为 UTF-8 JSON：

```json
{
  "v": 1,
  "op": "echo",
  "id": "flutter-1",
  "token": "session-token",
  "body": {
    "text": "hello"
  }
}
```

协议规则：

- `pair` 使用 Pair code `135790`，不带 token。
- `getInfo` 是开放能力发现接口，不带 token。
- `echo`、`telemetry`、`command` 需要带 Pair 后获得的 token。
- `setEventRule` 通过 `command` 发送，支持 `normal`、`quiet`、`burst`。
- 非 JSON payload 会被当作 raw payload，外设按 legacy echo 规则返回 `00 AA` + 原始 payload。

## 接收和解析

接收入口是 `_logIncoming(List<int> value, String label)`：

1. 如果前缀是 `00 AA`，按 legacy echo 解析。
2. 如果能解析成 JSON 协议 envelope，按协议消息解析。
3. 如果 `op=chunk`，交给 `BleChunkReassembler` 重组。
4. 其他内容按 raw 字节和文本展示。

Pair 成功后，项目会从响应 envelope 或 body 中捕获 token：

```dart
if (token != null && token.isNotEmpty && token != sessionToken) {
  sessionToken = token;
}
```

`getInfo` 响应会提取能力摘要，用于展示外设支持的 operations、commands、events 和 event rules。

## 大包和分片

BLE 单次 Notify/Write 的有效载荷受 MTU 限制。iOS/macOS 的 MTU 会自动协商，但仍不应该假设可以一次传输任意大小数据。

本项目约定 oversized Notify 使用 `op=chunk` 分片：

- `stream`: 分片流 ID。
- `index`: 当前分片序号。
- `count`: 总分片数。
- `encoding`: 当前使用 `base64`。
- `data`: base64 编码后的分片字节。

重组限制：

- 最多 8 个活跃 stream。
- 单个 stream 最多 256 个 part。
- 总缓存最多 64 KiB。

这些限制在 `BleChunkReassembler` 中实现，用于避免异常外设或错误数据导致内存无限增长。

## 调试流程

推荐验证步骤：

1. 启动 `../MacPeripheralOC/BLEPeripheral.xcodeproj`，让外设开始广播。
2. 在 Android 真机、iOS 真机或 macOS 运行 Flutter App。
3. 点击 `Scan`，找到 `MacBLE-Demo`。
4. 点击 `Connect`。
5. 等待自动 Notify On、Pair、Info。
6. 分别测试 `Ping`、`Echo`、`Telemetry`、`Command`、`Raw`、`Read`。
7. 点击 `Run Demo` 观察完整流程。

运行命令：

```bash
flutter run -d android
flutter run -d ios
flutter run -d macos
```

iOS 真机运行时需要有效签名配置。iOS 模拟器可以编译 UI 和插件工程，但不能验证真实 BLE 扫描和连接。Android 模拟器通常也不适合验证 BLE，建议使用 Android 真机。

## 常见问题

### 扫描不到设备

优先检查：

- 外设是否已经开始广播。
- 广播里是否包含 Service UUID `FFF0`。
- App 是否已获得蓝牙权限。
- iOS/Android 是否在真机运行。
- Android 设备是否开启蓝牙和附近设备权限。
- Central 和 Peripheral 是否不是同一台 Mac 上的两个本机 App。

### 能连接但没有数据

优先检查：

- 是否找到 Characteristic `FFF1`。
- 是否已经 `setNotifyValue(true)`。
- 外设是否支持对应 Characteristic 的 read/write/notify 属性。
- 写入是否使用了外设约定的 JSON envelope。
- token 保护接口是否已经先完成 Pair。

### 需要后台蓝牙吗

当前项目没有开启 iOS 后台蓝牙。若未来需要后台处理 BLE 事件，需要额外配置 `UIBackgroundModes` 的 `bluetooth-central`，并重新评估系统唤醒、耗电和 App Store 审核说明。
