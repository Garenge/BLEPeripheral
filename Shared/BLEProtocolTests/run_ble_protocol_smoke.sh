#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="${TMPDIR:-/tmp}/ble_protocol_smoke"
BIN="$OUT_DIR/ble_protocol_smoke"

mkdir -p "$OUT_DIR"

clang \
  -fobjc-arc \
  -framework Foundation \
  "$SCRIPT_DIR/ble_protocol_smoke.m" \
  "$REPO_ROOT/Shared/BLEProtocol/BLEProtocolConstants.m" \
  "$REPO_ROOT/Shared/BLEProtocol/BLEProtocolMessage.m" \
  "$REPO_ROOT/Shared/BLEProtocol/BLEProtocolHandler.m" \
  -o "$BIN"

"$BIN"
