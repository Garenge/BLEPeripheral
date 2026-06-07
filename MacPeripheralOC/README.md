# Mac BLE Peripheral

macOS app that advertises `MacBLE-Demo` and exposes one GATT service for iPhone Central testing.

## Open

`BLEPeripheral.xcodeproj` in this folder.

## GATT 概况（当前 Demo）

| 项 | 值 |
|----|-----|
| 广播名 | `MacBLE-Demo` |
| 主服务 UUID | `0000FFF0-0000-1000-8000-00805F9B34FB`（短 UUID **FFF0**） |
| 特征 UUID | `0000FFF1-0000-1000-8000-00805F9B34FB`（短 UUID **FFF1**） |
| 服务类型 | Primary（唯一服务） |
| 特征属性 | `read`、`write`、`writeWithoutResponse`、`notify` |
| 手机写入 | 协议推荐 **Write 带响应**（ATT 仅 ACK，不带 JSON） |
| Mac 业务回复 | **Notify**（已订阅）或 **Read FFF1**（最后一次响应） |
| 权限 | 可读、可写 |
| 初始 Read 值 | `00 AA`（空 legacy 回显） |
| 订阅后 Notify | 推送最近响应，并推送 JSON `op=event` session 事件 |
| 写入 | JSON 协议请求 → 响应写入特征值；若已订阅则 **定向 notify 推送响应**；非协议 payload 走 legacy `00 AA` 回显 |
| 安全规则 | `pair` code `135790` → session token；`echo`/`telemetry`/`command` 需携带 token |
| 能力发现 | `getInfo` 无需 token，返回 `operations`、`commands`、`events`、`eventRules`、`security`、`transport` |

启动后日志窗口会打印 `--- Mac BLE GATT profile ---` 摘要（与上表一致）。

## 连接与「自动断开」

**本应用没有实现自动断开计时器。**

- Mac 作为 **Peripheral**，不会主动在 N 秒后踢掉 iPhone。
- 连接/断开由 **Central（iPhone）** 或系统蓝牙栈决定：用户在 App 里 Disconnect、关蓝牙、走远等。
- **取消订阅 notify** 只会停止 Mac 上 2 秒一次的 `tick` 推送；**不等于断开 BLE 连接**（链路可能仍连着，直到 Central 真正 disconnect）。
- 调用 `stop`（若以后加 UI）会停广播并 `removeAllServices`，已连接端会异常，但当前启动后一直广播，无 idle 断连。

若需要「空闲 N 秒自动断连」，属于尚未实现的功能，需在 Peripheral 侧配合 Central 行为或文档约定另行开发。

## 日志标签

窗口日志使用统一前缀，便于过滤：

| 标签 | 含义 |
|------|------|
| `[LINK+]` | Central 首次出现或 notify 订阅（Peripheral 无系统级 connect 回调，以首次 GATT 交互为准） |
| `[LINK-]` | 取消 notify；或 App `stop` 时清理所有已跟踪 Central |
| `[LINK]` | 链路提示（例如取消订阅后链路可能仍在） |
| `[RX]` | 收到 Central 数据（read / write） |
| `[TX]` | 发往 Central（read 响应、write 响应、notify/tick） |
| `[SYS]` | 本机状态（蓝牙、广播、定时器） |

每条 `[RX]`/`[TX]` 含：`central` UUID、通道名、字节数、UTF-8 预览（非文本则 hex）。

**说明：** macOS `CBPeripheralManager` 不提供可靠的「Central 已断链」委托；iPhone 完全断开后通常不再有 read/write，但 Mac 端不一定收到 `[LINK-] disconnected`。取消 notify 会明确打 `[LINK-] notify OFF`。

## iPhone 三方 App 扫不到 Mac？

1. Mac 端 App **保持前台运行**，日志里有 `Advertising active (isAdvertising=YES)`。
2. 三方 App 用 **扫描全部设备**（不要只按自定义名称过滤；名称可能是 `MacBLE-Demo` 或暂时显示 Unknown）。
3. 广播包只有约 **28 字节**：已改为 **16 位 FFF0 + 设备名**，避免 128 位 UUID 把名称挤进 overflow 导致通用扫描看不到。
4. 连接后在 App 里打开服务 **FFF0**（完整 UUID 与 GATT 一致），特征 **FFF1**。
5. 系统设置 → 蓝牙：Mac 与 iPhone 均开启；Mac 隐私 → 蓝牙允许本 App。

## 连接后没有日志？

1. **启动后** 应至少看到 `[SYS] Log window ready` 和 `--- Mac BLE GATT profile ---`。若没有，请 Clean Build 后重新 Run，并看 Console.app 里 `BLEPeripheral:` 前缀。
2. **仅 iPhone 显示 Connected 不够** — Mac Peripheral **不会**在链路建立时打 `[LINK+]`，必须在 **FFF1** 上 **Read / Write / Subscribe** 才有 `[RX]`/`[TX]`/`[LINK+]`。
3. 使用本仓库 **BLECentral** iOS App：发现特征后会 **自动订阅 Notify + Pair**，Mac 应出现 `[LINK+]`、`[RX] write/FFF1`、`[AUTH]`/`[TX] notify/event` 相关日志。
4. 系统设置 → 隐私与安全性 → **蓝牙** → 允许 BLEPeripheral；本工程已加 `BLEPeripheral.entitlements`（蓝牙 + App Sandbox）。

## Sources

- `BLEPeripheral/` — app UI and `BLEPeripheralController`
- `../Shared/BLEProtocol/` — JSON protocol (Mac compiles `BLEProtocolHandler` too)

## Run

Scheme **BLEPeripheral** → **My Mac**. Requires Bluetooth permission and powered-on Bluetooth.

Legacy raw FFF1 rule: [../ble_simple_echo.md](../ble_simple_echo.md)  
JSON protocol and session events: [../ble_protocol.md](../ble_protocol.md)
