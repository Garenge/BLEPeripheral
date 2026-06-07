# BLEProtocol Smoke Tests

Lightweight Objective-C CLI smoke tests for the shared BLE JSON protocol.

## Run

```bash
Shared/BLEProtocolTests/run_ble_protocol_smoke.sh
```

The script compiles the shared protocol sources with `clang` and writes the temporary binary under `${TMPDIR:-/tmp}/ble_protocol_smoke`.
It also loads `ble_payload_fixtures.json`, a small set of recorded base64 BLE payload samples shared with the Flutter protocol tests.

## Coverage

- `pair` succeeds with the default demo code and returns a token.
- Protected `echo` rejects missing tokens.
- Protected `echo` succeeds with a matching token.
- `getInfo` advertises operation groups, commands, events, and rule modes.
- `command resetCounters` returns command metadata.
- `command setEventRule` accepts `normal`/`quiet`/`burst` and rejects invalid modes.
- `command` without `body.name` returns `invalid_body` and does not mark a side effect.
- `op=chunk` envelopes decode and recorded chunk fixtures reassemble to the original payload.
