#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_XCODE=0
TMP_ROOT="${TMPDIR:-/tmp}"
LOG_DIR="${TMP_ROOT%/}/ble_suite_verify_logs"

for arg in "$@"; do
  case "$arg" in
    --xcode)
      RUN_XCODE=1
      ;;
    -h|--help)
      echo "Usage: scripts/verify_ble_suite.sh [--xcode]"
      echo "Runs shared protocol smoke tests, Flutter tests, and Flutter analysis."
      echo "Pass --xcode to also build Mac Peripheral, Mac Central, and iOS Central."
      echo "Xcode build logs are stored under ${LOG_DIR} and printed only on failure."
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

run_step() {
  local label="$1"
  shift
  echo "==> $label"
  "$@"
}

run_logged_step() {
  local label="$1"
  local log_name="$2"
  shift 2
  local log_file="$LOG_DIR/$log_name"

  mkdir -p "$LOG_DIR"
  echo "==> $label"
  if "$@" >"$log_file" 2>&1; then
    echo "    ok (log: $log_file)"
    return 0
  fi

  local status=$?
  echo "    failed (log: $log_file)" >&2
  cat "$log_file" >&2
  return "$status"
}

run_step "Objective-C protocol smoke tests" "$REPO_ROOT/Shared/BLEProtocolTests/run_ble_protocol_smoke.sh"

pushd "$REPO_ROOT/FlutterCentral" >/dev/null
run_step "Flutter tests" flutter test
run_step "Flutter analysis" flutter analyze
popd >/dev/null

if [[ "$RUN_XCODE" -eq 1 ]]; then
  run_logged_step "Build Mac Peripheral" "mac_peripheral.log" \
    xcodebuild \
      -project "$REPO_ROOT/MacPeripheralOC/BLEPeripheral.xcodeproj" \
      -scheme BLEPeripheral \
      -configuration Debug \
      -derivedDataPath "$REPO_ROOT/build/MacPeripheral" \
      build

  run_logged_step "Build Mac Central" "mac_central.log" \
    xcodebuild \
      -project "$REPO_ROOT/MacCentralOC/MacCentralOC.xcodeproj" \
      -scheme MacCentralOC \
      -configuration Debug \
      -derivedDataPath "$REPO_ROOT/build/MacCentral" \
      build

  run_logged_step "Build iOS Central simulator" "ios_central_simulator.log" \
    xcodebuild \
      -project "$REPO_ROOT/iOSCentralOC/BLECentral.xcodeproj" \
      -scheme BLECentral \
      -configuration Debug \
      -sdk iphonesimulator \
      -derivedDataPath "$REPO_ROOT/build/iOSCentral" \
      CODE_SIGNING_ALLOWED=NO \
      build
fi

echo "==> BLE suite verification passed"
