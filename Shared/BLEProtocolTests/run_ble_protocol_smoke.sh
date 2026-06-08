#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="${TMPDIR:-/tmp}/ble_protocol_smoke"
BIN="$OUT_DIR/ble_protocol_smoke"
FIXTURES="$SCRIPT_DIR/ble_payload_fixtures.json"
VERBOSE=0

for arg in "$@"; do
  case "$arg" in
    --verbose)
      VERBOSE=1
      ;;
    -h|--help)
      echo "Usage: Shared/BLEProtocolTests/run_ble_protocol_smoke.sh [--verbose]"
      echo "Compiles and runs the shared Objective-C BLE protocol smoke tests."
      echo "Pass --verbose to print every passing assertion."
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$OUT_DIR"

clang \
  -fobjc-arc \
  -framework Foundation \
  "$SCRIPT_DIR/ble_protocol_smoke.m" \
  "$REPO_ROOT/Shared/BLEProtocol/BLEProtocolConstants.m" \
  "$REPO_ROOT/Shared/BLEProtocol/BLEProtocolMessage.m" \
  "$REPO_ROOT/Shared/BLEProtocol/BLEProtocolHandler.m" \
  -o "$BIN"

BLE_PAYLOAD_FIXTURES="$FIXTURES" BLE_PROTOCOL_SMOKE_VERBOSE="$VERBOSE" "$BIN"
