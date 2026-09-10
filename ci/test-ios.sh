#!/usr/bin/env bash
set -euo pipefail

cd "${CM_BUILD_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
mkdir -p build

DEVICE_UDID="$(
  xcrun simctl list devices available -j | python3 -c '
import json
import sys

devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    for device in devices[runtime]:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit("Ingen tilgjengelig iPhone-simulator ble funnet")
'
)"

echo "Kjører tester på simulator $DEVICE_UDID"
RESULT_BUNDLE_PATH="build/TestResults-$(date +%s).xcresult"
BUILD_LOG_PATH="build/xcodebuild-test.log"
if xcodebuild test \
  -project MealShuffler.xcodeproj \
  -scheme MealShuffler \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$DEVICE_UDID" \
  -resultBundlePath "$RESULT_BUNDLE_PATH" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$BUILD_LOG_PATH"; then
  exit 0
else
  build_status=$?
fi

# Keep compiler diagnostics visible at the end, after Xcode's long copy/link output.
echo "Build/test failure details (full log: $BUILD_LOG_PATH):"
grep -n -B 2 -A 6 -E 'error:|Testing failed:|Test Case .* failed|failed -' "$BUILD_LOG_PATH" || true
exit "$build_status"
