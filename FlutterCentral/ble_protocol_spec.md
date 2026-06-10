# BLE Protocol Spec

本文是 `MacBLE-Demo` 外设与 FlutterCentral 移动端之间的 BLE 协议规范。规范来源于：

- `../MacPeripheralOC/BLEPeripheral/BLEPeripheralController.m`
- `../Shared/BLEProtocol/BLEProtocolConstants.m`
- `../Shared/BLEProtocol/BLEProtocolHandler.m`
- `../Shared/BLEProtocol/BLEProtocolMessage.m`

## 1. GATT Profile

| Item | Value |
| --- | --- |
| Peripheral name | `MacBLE-Demo` |
| Advertised service | `FFF0` 16-bit UUID |
| Primary service UUID | `0000FFF0-0000-1000-8000-00805F9B34FB` |
| Characteristic UUID | `0000FFF1-0000-1000-8000-00805F9B34FB` |
| Characteristic properties | `read`, `write`, `writeWithoutResponse`, `notify` |
| Characteristic permissions | readable, writeable |

传输约定：

- Central 扫描时优先按 Service `FFF0` 过滤，也可以用名称 `MacBLE-Demo` 辅助识别。
- Central 连接后必须发现 Service `FFF0` 和 Characteristic `FFF1`。
- 数据写入统一写到 Characteristic `FFF1`。
- 外设优先通过 Notify 推送回复；未开启 Notify 时，回复会保存在 Characteristic 当前值中，可通过 Read 读取。
- 协议写入推荐使用 write with response；外设也声明支持 write without response。

## 2. 单客户端策略

Mac Peripheral 当前只允许一个 Central 占用业务会话：

1. 空闲时广播 `MacBLE-Demo` 和 Service `FFF0`。
2. 第一个可识别 Central 访问 `FFF1` 后成为 owner；触发点包括 Read、Write、Notify 订阅。Flutter / iOS / Android 产品端连接后应立即开启 Notify 并 Pair，让占用尽早成立。
3. owner 建立后 Peripheral 停止广播，所以第二个客户端通常扫描不到该外设。
4. 如果第二个客户端来自缓存扫描结果、或已经提前连上，继续 Read/Write `FFF1` 会被外设按 ATT 权限错误拒绝；产品端应提示设备正被其他客户端使用。
5. owner 取消 Notify 后释放占用，Peripheral 恢复广播；外设 App `stop` 也会释放占用。

限制说明：macOS `CBPeripheralManager` 没有可靠的「Central 已连接」回调，也可能在 Read/Write 请求里不暴露 `request.central`。因此外设以首次可识别 GATT 行为作为占用点；无法识别来源的 Read/Write 会记录 `central=nil`，并按当前 owner session 处理。

## 3. 数据格式

协议 payload 是 UTF-8 JSON object。请求 envelope：

```json
{
  "v": 1,
  "op": "echo",
  "id": "client-message-id",
  "token": "optional-session-token",
  "body": {}
}
```

成功响应 envelope：

```json
{
  "v": 1,
  "op": "echo",
  "id": "client-message-id",
  "ok": true,
  "token": "optional-session-token",
  "body": {}
}
```

错误响应 envelope：

```json
{
  "v": 1,
  "op": "error",
  "id": "client-message-id",
  "ok": false,
  "err": {
    "code": "invalid_body",
    "message": "echo requires body.text string."
  }
}
```

字段说明：

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `v` | integer | yes | 协议版本，目前固定为 `1` |
| `op` | string | yes | 操作名或响应名 |
| `id` | string | recommended | 请求 ID；缺失或空字符串时外设按 `0` 处理 |
| `token` | string | conditional | 受保护操作需要 session token |
| `body` | object | yes | 操作参数或响应数据，缺失时按 `{}` 处理 |
| `ok` | boolean | response | 响应是否成功 |
| `err` | object | error response | 错误码和错误说明 |

Token 可以放在 envelope 顶层 `token`，也可以放在 `body.token`。移动端应优先使用顶层 `token`。

## 4. Pair 和安全规则

默认 Pair code：

```text
135790
```

开放操作：

- `pair`
- `ping`
- `getInfo`

受保护操作：

- `echo`
- `telemetry`
- `command`

Pair 请求：

```json
{
  "v": 1,
  "op": "pair",
  "id": "pair-1",
  "body": {
    "code": "135790"
  }
}
```

Pair 成功响应：

```json
{
  "v": 1,
  "op": "paired",
  "id": "pair-1",
  "ok": true,
  "token": "session-token",
  "body": {
    "session": "session-id",
    "token": "session-token",
    "expires": "when BLE app restarts or session is replaced"
  }
}
```

Pair code 不匹配时返回：

```json
{
  "v": 1,
  "op": "error",
  "id": "pair-1",
  "ok": false,
  "err": {
    "code": "pairing_failed",
    "message": "Pair code mismatch."
  }
}
```

未配对调用受保护操作时返回 `unauthorized`。

## 5. Operations

### `ping`

请求：

```json
{
  "v": 1,
  "op": "ping",
  "id": "ping-1",
  "body": {}
}
```

响应 `pong`：

```json
{
  "v": 1,
  "op": "pong",
  "id": "ping-1",
  "ok": true,
  "body": {
    "ts": 1781010000,
    "platform": "macOS",
    "session": "session-id"
  }
}
```

### `getInfo`

请求：

```json
{
  "v": 1,
  "op": "getInfo",
  "id": "info-1",
  "body": {}
}
```

响应 `info` 的 body 包含：

- `name`
- `serviceUUID`
- `characteristicUUID`
- `protocolVersion`
- `pairing`
- `session`
- `eventRuleMode`
- `requiresToken`
- `capabilitySchema`
- `security`
- `operations`
- `commands`
- `events`
- `eventRules`
- `eventRuleModes`
- `transport`

移动端应在连接后主动请求 `getInfo`，用响应校准 UI 能力展示。

### `echo`

受保护操作。请求：

```json
{
  "v": 1,
  "op": "echo",
  "id": "echo-1",
  "token": "session-token",
  "body": {
    "text": "hello"
  }
}
```

响应 `echo`：

```json
{
  "v": 1,
  "op": "echo",
  "id": "echo-1",
  "ok": true,
  "token": "session-token",
  "body": {
    "text": "hello"
  }
}
```

`body.text` 必须是非空字符串，否则返回 `invalid_body`。

### `telemetry`

受保护操作。请求：

```json
{
  "v": 1,
  "op": "telemetry",
  "id": "telemetry-1",
  "token": "session-token",
  "body": {}
}
```

响应 `telemetry` body：

```json
{
  "session": "session-id",
  "eventRuleMode": "normal",
  "reads": 0,
  "writes": 3,
  "notifies": 4,
  "events": 2,
  "uptimeHint": "session scoped",
  "ts": 1781010000
}
```

### `command`

受保护操作。请求：

```json
{
  "v": 1,
  "op": "command",
  "id": "command-1",
  "token": "session-token",
  "body": {
    "name": "identify"
  }
}
```

响应 `commandResult` body：

```json
{
  "name": "identify",
  "accepted": true,
  "session": "session-id",
  "queuedEvent": 3,
  "effect": "push identify event",
  "eventRuleMode": "normal",
  "message": "Command accepted by demo peripheral."
}
```

支持的 command：

| Command | Body | Effect | Event |
| --- | --- | --- | --- |
| `identify` | `{ "name": "identify" }` | 推送识别事件 | `command.identify` |
| `sample` | `{ "name": "sample" }` | 推送示例遥测事件 | `command.sample` |
| `resetCounters` | `{ "name": "resetCounters" }` | 清空当前 session 的读写通知事件计数 | `command.resetCounters` |
| `setEventRule` | `{ "name": "setEventRule", "mode": "normal" }` | 切换事件规则 | `event.ruleChanged` |

未知 command 会返回 `accepted: false`，但响应仍是 `ok: true` 的 `commandResult`。

`setEventRule` 的 `mode` 只能是：

- `normal`
- `quiet`
- `burst`

非法 mode 返回 `invalid_body`。

## 6. Events

事件通过 Notify 推送，envelope `op` 为 `event`：

```json
{
  "v": 1,
  "op": "event",
  "id": "event-1",
  "ok": true,
  "body": {
    "type": "paired",
    "n": 1,
    "ts": 1781010000,
    "session": "session-id",
    "eventRuleMode": "normal"
  }
}
```

事件类型：

| Type | Trigger |
| --- | --- |
| `subscribed` | Central 开启 Notify |
| `paired` | Pair 成功 |
| `write` | 协议或 legacy 写入 |
| `command.identify` | `command identify` |
| `command.sample` | `command sample` |
| `command.sample.detail` | `eventRuleMode=burst` 且执行 `sample` |
| `command.resetCounters` | `command resetCounters` |
| `event.ruleChanged` | `command setEventRule` |

事件规则：

- `normal`: 正常推送 write 事件和 command 事件。
- `quiet`: 抑制普通 write 事件，但保留 paired 和 ruleChanged。
- `burst`: 执行 `sample` 时额外推送 `command.sample.detail`。

## 7. Chunk 分片

当 Notify payload 大于当前 Central 的 `maximumUpdateValueLength` 时，外设会将原始 payload 分成多个 `chunk` envelope：

```json
{
  "v": 1,
  "op": "chunk",
  "id": "chunk-session-1-0",
  "ok": true,
  "body": {
    "stream": "session-1",
    "index": 0,
    "count": 2,
    "encoding": "base64",
    "data": "..."
  }
}
```

字段说明：

| Field | Type | Description |
| --- | --- | --- |
| `stream` | string | 分片流 ID |
| `index` | integer | 当前分片序号，从 0 开始 |
| `count` | integer | 总分片数量，必须大于 0 |
| `encoding` | string | 当前固定为 `base64` |
| `data` | string | 当前分片的 base64 数据 |

外设限制：

- 默认 Notify 最大包长兜底值为 185 字节。
- 单个 stream 最多 256 个分片。
- 每个 Central 的 Notify 队列最多保留 256 个 packet，超出时丢弃最旧 packet。

移动端限制：

- 最多缓存 8 个活跃 stream。
- 单个 stream 最多 256 个分片。
- 总缓存最多 64 KiB。
- 收齐后按 `index` 顺序拼接原始 payload，再重新进入协议解析流程。

## 8. Legacy Raw Echo

如果写入数据不是合法协议 envelope，外设进入 legacy echo 模式：

```text
response = 0x00 0xAA + original_payload
```

例如写入 UTF-8 文本 `raw`，响应字节是：

```text
00 AA 72 61 77
```

移动端应把该模式作为调试/兼容能力，不作为主要产品流程。

## 9. 错误码

| Code | Meaning |
| --- | --- |
| `invalid_json` | payload 不是合法 JSON object |
| `invalid_envelope` | 缺少 numeric `v` 或 string `op`，或协议版本不支持 |
| `unknown_op` | 未知 operation |
| `invalid_body` | body 缺少必需字段或字段类型错误 |
| `unauthorized` | 受保护 operation 未携带有效 token |
| `pairing_failed` | Pair code 不匹配 |

## 10. 推荐移动端流程

1. 扫描 Service `FFF0`。
2. 展示 `MacBLE-Demo` 或符合 Service 过滤的候选设备。
3. 连接设备。
4. 发现 Service `FFF0` 和 Characteristic `FFF1`。
5. 监听 `onValueReceived`。
6. 开启 Notify。
7. 发送 `pair`。
9. 捕获 token。
10. Read 一次当前值或等待 Notify 响应。
11. 发送 `getInfo`。
12. 根据 `info` 渲染能力、命令和事件规则。
13. 执行 `ping`、`echo`、`telemetry`、`command` 等产品功能。
14. 将 raw echo、Read、Notify On/Off、协议日志放入高级调试入口。
