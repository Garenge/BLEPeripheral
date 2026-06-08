# BLE JSON Protocol (v1)

Mac peripheral (`BLEPeripheral`) and all first-party Central apps (Mac Objective-C, iOS Objective-C, Flutter macOS) share this UTF-8 JSON envelope over characteristic `FFF1`.

## Transport / 回复语义（重要）

GATT 特征 **FFF1** 当前属性：`read` + `write` + `writeWithoutResponse` + `notify`。

| 方向 | 推荐方式 | 说明 |
|------|----------|------|
| 手机 → Mac（请求） | **Write With Response**（带响应的写） | ATT 只回「成功/失败」，**不回** JSON 正文 |
| Mac → 手机（业务回复） | **Notify**（已订阅时） | 推送与请求对应的 JSON 响应；协议首选 |
| Mac → 手机（业务回复） | **Read FFF1** | 读特征当前值 = 最近一次处理后的响应字节 |
| 事件推送 | **Notify** | Mac 推送 `op=event`，用于订阅、配对、写入等 session 事件 |
| 长 Notify payload | **`op=chunk` 分片** | payload 超过 Central 的 `maximumUpdateValueLength` 时，Mac 按 stream 分片；first-party clients 自动重组后再解析原始 JSON/legacy payload |

**结论（我们定义的用法）：**

1. **需要 ATT 应答**：协议命令请用 **Write（带响应）**；Mac 在 `didReceiveWriteRequests` 里 `respondToRequest(Success)`，表示「收到了」。
2. **不需要在 ATT 里带 JSON 回复**：应用层正文通过 **更新特征值 + Notify** 交给手机；手机应 **订阅 Notify** 或 **再 Read 一次 FFF1**。
3. **Write Without Response**：特征也支持，Mac 仍处理内容并同样通过 Notify/Read 回复，但链路层无 Write 应答，不适合需要「确认送达」的命令。

三方调试 App：对 FFF1 发数据时选 **Write**（不要只发 Write No Response，除非明确做 fire-and-forget）；并 **打开 Notify** 才能实时看到 Mac 的 JSON 回复。写入非协议 payload 会进入 legacy `00 AA + 原始字节` 回显模式。

## Security / Session Rule

This is a learning/demo security layer, not production cryptography.

- Default pair code: `135790`
- First-party clients auto-send `pair` after FFF1 notify is enabled.
- First-party clients auto-send `getInfo` during connection setup to discover capabilities.
- `pair` returns a session `token` in both the top-level envelope and `body.token`.
- Protected operations must include that string `token`.
- Non-string `token` values are ignored and therefore fail protected operations as `unauthorized`.
- `ping` and `getInfo` stay open for diagnostics.
- Session token is scoped to the current peripheral app runtime and Central UUID-derived session.

## Envelope

Request:

```json
{
  "v": 1,
  "op": "echo",
  "id": "ios-1",
  "token": "tok-12345678",
  "body": { "text": "hello" }
}
```

Success response:

```json
{
  "v": 1,
  "op": "echo",
  "id": "ios-1",
  "ok": true,
  "token": "tok-12345678",
  "body": { "text": "hello" }
}
```

Error response:

```json
{
  "v": 1,
  "op": "error",
  "id": "ios-1",
  "ok": false,
  "err": { "code": "unknown_op", "message": "Unknown op: foo" }
}
```

## Operations

| `op` (request) | `op` (response) | `body` (request) | `body` (response) |
|----------------|-----------------|------------------|-------------------|
| `pair` | `paired` | `code` string | `session`, `token`, `expires` |
| `ping` | `pong` | optional | `ts` (unix seconds), `platform`, `session` |
| `getInfo` | `info` | optional | GATT/profile metadata plus `capabilitySchema`, `operations`, `commands`, `events`, `eventRules`, `security`, `transport` |
| `echo` | `echo` | `text` string, requires token | same `text` |
| `telemetry` | `telemetry` | optional, requires token | session-scoped `reads`, `writes`, `notifies`, `events`, `eventRuleMode`, `ts` |
| `command` | `commandResult` | `name` string, requires token | `name`, `accepted`, `session`, `queuedEvent`, `eventRuleMode`, `message` |

Server may also push `event` notifications (no request), with:

```json
{
  "v": 1,
  "op": "event",
  "id": "event-1",
  "ok": true,
  "body": {
    "type": "paired",
    "n": 1,
    "ts": 1710000000,
    "session": "mac-abc12345"
  }
}
```

Event types currently include `subscribed`, `paired`, `write`, `command.identify`, `command.sample`, `command.sample.detail`, `command.resetCounters`, and `event.ruleChanged`.

Server may also push `chunk` notifications when a reply/event is larger than the Central's negotiated notify update length. Each chunk body is:

```json
{
  "v": 1,
  "op": "chunk",
  "id": "chunk-mac-abc12345-1-0",
  "ok": true,
  "body": {
    "stream": "mac-abc12345-1",
    "index": 0,
    "count": 3,
    "encoding": "base64",
    "data": "eyJ2IjoxLCJvcCI6..."
  }
}
```

`index` is zero-based. `index` and `count` must be JSON numbers that represent non-negative integers, and booleans/fractional/negative values are rejected by first-party decoders. Receivers collect all chunks with the same `stream`, concatenate decoded `data` by `index`, then parse the reassembled bytes through the normal protocol/legacy path. First-party Mac, iOS, and Flutter Central clients log chunk progress and `chunk complete`; they also cap incomplete reassembly state to 8 active streams, 256 parts per stream, and 64 KiB total buffered chunk bytes, trimming or dropping over-limit streams with a reasoned log line.

## Capability Discovery

`getInfo` is intentionally open so scanner tools and first-party clients can learn the profile before pairing. The `info.body` capability fields are:

| field | meaning |
|-------|---------|
| `capabilitySchema` | Discovery schema identifier, currently `ble-demo.capabilities.v1` |
| `operations.open` | Operations accepted without a token: `pair`, `ping`, `getInfo` |
| `operations.protected` | Operations requiring a token: `echo`, `telemetry`, `command` |
| `operations.responses` | Request-to-response operation map |
| `commands` | Supported demo command descriptors with emitted event type |
| `events` | Server event descriptors and triggers |
| `eventRules` | Human-readable event association rules |
| `eventRuleModes` | Supported session modes: `normal`, `quiet`, `burst` |
| `security` | Pairing/token placement and scope hints |
| `transport` | Scan/write/notify/read behavior and legacy fallback |

## Event Rule Modes

The event rule mode is per Central session. It defaults to `normal`, appears in `info`, `telemetry`, `commandResult`, and event bodies, and can be changed with:

```json
{
  "v": 1,
  "op": "command",
  "id": "ios-7",
  "token": "tok-12345678",
  "body": { "name": "setEventRule", "mode": "burst" }
}
```

| mode | behavior |
|------|----------|
| `normal` | Default: replies plus write/session events and command-specific events. |
| `quiet` | Suppresses ordinary `write` events while keeping pair and rule-change events. |
| `burst` | Keeps normal behavior and adds `command.sample.detail` after `command sample`. |

First-party Mac, iOS, and Flutter Central apps keep this mode visible with a selectable segmented control.

Supported demo commands:

| command | side effect |
|---------|-------------|
| `identify` | Pushes a `command.identify` event with peripheral/service/characteristic identity. |
| `sample` | Pushes a `command.sample` event with simulated battery/RSSI/temperature data. |
| `resetCounters` | Resets the current session counters and pushes before/after counts. |
| `setEventRule` | Switches `eventRuleMode` to `normal`, `quiet`, or `burst`, then pushes `event.ruleChanged`. |

## Error codes

- `invalid_json` — payload is not valid JSON object
- `invalid_envelope` — missing/invalid `v` or `op`, or unsupported version
- `invalid_body` — operation-specific body validation failed
- `unknown_op` — unsupported `op`; returned before token checks so typo diagnostics stay visible
- `unauthorized` — token is missing or does not match the current session
- `pairing_failed` — pair code mismatch

## Legacy mode

If a write is not a protocol envelope (numeric `v` + string `op`), Mac treats it as **legacy raw bytes**: stores bytes and echoes `00 AA` + original payload on notify or read.

This keeps generic BLE scanner apps useful while the first-party apps exercise the JSON protocol.

## Implementation

Shared codec (both apps compile from `Shared/BLEProtocol/`):

- `BLEProtocolMessage.h` — encode/decode envelope
- `BLEProtocolHandler.h` — Mac peripheral request handler and session-aware response result

The Flutter client mirrors the same envelope in Dart.
