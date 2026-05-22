# BLE JSON Protocol (v1)

Mac peripheral (`BLEPeripheral`) and iPhone central (`BLECentral`) share this UTF-8 JSON envelope over characteristic `FFF1`.

## Transport / 回复语义（重要）

GATT 特征 **FFF1** 当前属性：`read` + `write` + `writeWithoutResponse` + `notify`。

| 方向 | 推荐方式 | 说明 |
|------|----------|------|
| 手机 → Mac（请求） | **Write With Response**（带响应的写） | ATT 只回「成功/失败」，**不回** JSON 正文 |
| Mac → 手机（业务回复） | **Notify**（已订阅时） | 推送与请求对应的 JSON 响应；协议首选 |
| Mac → 手机（业务回复） | **Read FFF1** | 读特征当前值 = 最近一次处理后的响应字节 |
| 周期推送 | **Notify** | Mac 每 2s 推送 `op=tick`（与请求无关） |

**结论（我们定义的用法）：**

1. **需要 ATT 应答**：协议命令请用 **Write（带响应）**；Mac 在 `didReceiveWriteRequests` 里 `respondToRequest(Success)`，表示「收到了」。
2. **不需要在 ATT 里带 JSON 回复**：应用层正文通过 **更新特征值 + Notify** 交给手机；手机应 **订阅 Notify** 或 **再 Read 一次 FFF1**。
3. **Write Without Response**：特征也支持，Mac 仍处理内容并同样通过 Notify/Read 回复，但链路层无 Write 应答，不适合需要「确认送达」的命令。

三方调试 App：对 FFF1 发数据时选 **Write**（不要只发 Write No Response，除非明确做 fire-and-forget）；并 **打开 Notify** 才能实时看到 Mac 的 JSON 回复。

## Envelope

Request:

```json
{
  "v": 1,
  "op": "ping",
  "id": "ios-1",
  "body": {}
}
```

Success response:

```json
{
  "v": 1,
  "op": "pong",
  "id": "ios-1",
  "ok": true,
  "body": { "ts": 1710000000, "platform": "macOS" }
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
| `ping` | `pong` | optional | `ts` (unix seconds), `platform` |
| `echo` | `echo` | `text` (required string) | same `text` |
| `getInfo` | `info` | optional | `name`, `serviceUUID`, `characteristicUUID`, `protocolVersion` |

Server may also push `tick` notifications (no request), with `body.n` sequence and `body.ts`.

## Error codes

- `invalid_json` — payload is not valid JSON object
- `invalid_envelope` — missing/invalid `v` or `op`, or unsupported version
- `invalid_body` — operation-specific body validation failed
- `unknown_op` — unsupported `op`

## Legacy mode

If a write is valid JSON but not a protocol envelope (no numeric `v` + string `op`), Mac treats it as **legacy raw text**: stores bytes and echoes on notify when subscribed.

Non-JSON UTF-8 writes use the same legacy path.

## Implementation

Shared codec (both apps compile from `Shared/BLEProtocol/`):

- `BLEProtocolMessage.h` — encode/decode envelope
- `BLEProtocolHandler.h` — Mac peripheral request handler (Mac target only)

Periodic notify on Mac uses `tick` JSON instead of plain text.
