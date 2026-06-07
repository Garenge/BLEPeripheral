#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_XCODE=0

for arg in "$@"; do
  case "$arg" in
    --xcode)
      RUN_XCODE=1
      ;;
    -h|--help)
      echo "Usage: scripts/verify_ble_suite.sh [--xcode]"
      echo "Runs shared protocol smoke tests, Flutter tests, and Flutter analysis."
      echo "Pass --xcode to also build Mac Peripheral, Mac Central, and iOS Central."
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

run_step "Objective-C protocol smoke tests" "$REPO_ROOT/Shared/BLEProtocolTests/run_ble_protocol_smoke.sh"

pushd "$REPO_ROOT/FlutterCentral" >/dev/null
run_step "Flutter tests" flutter test
run_step "Flutter analysis" flutter analyze
popd >/dev/null

if [[ "$RUN_XCODE" -eq 1 ]]; then
  run_step "Build Mac Peripheral" \
    xcodebuild \
      -project "$REPO_ROOT/MacPeripheralOC/BLEPeripheral.xcodeproj" \
      -scheme BLEPeripheral \
      -configuration Debug \
      -derivedDataPath "$REPO_ROOT/build/MacPeripheral" \
      build

  run_step "Build Mac Central" \
    xcodebuild \
      -project "$REPO_ROOT/MacCentralOC/MacCentralOC.xcodeproj" \
      -scheme MacCentralOC \
      -configuration Debug \
      -derivedDataPath "$REPO_ROOT/build/MacCentral" \
      build

  run_step "Build iOS Central simulator" \
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
