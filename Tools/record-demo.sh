#!/usr/bin/env bash
# Regenerates Docs/demo.gif: resets a dedicated simulator, stages photos that
# match the demo trip, drives the app through DemoWalkthrough while recording,
# then turns the capture into a GIF.
#
# Usage: Tools/record-demo.sh
#
# Env overrides:
#   SPEEDUP=1.6                 playback rate of the finished GIF
#   FPS=10                      frames per second in the GIF
#   WIDTH=300                   GIF width in pixels
#   KEEP_CAPTURE=1              keep the .mov so it can be re-encoded without re-recording
#   DEVICE_TYPE="iPhone 17 Pro" device model for the demo simulator
set -euo pipefail

SPEEDUP="${SPEEDUP:-1.6}"
FPS="${FPS:-10}"
WIDTH="${WIDTH:-300}"
DEVICE_TYPE="${DEVICE_TYPE:-iPhone 17 Pro}"
SIM_NAME="Journey Demo"
BUNDLE_ID="com.carlopascoli.journey"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/DerivedData"
WORK="$(mktemp -d)"
if [ "${KEEP_CAPTURE:-0}" != "1" ]; then
  trap 'rm -rf "$WORK"' EXIT
fi

# The demo simulator is erased on every run, so never point this at one you use.
DEVICE=$(xcrun simctl list devices available \
  | grep "$SIM_NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)
if [ -z "$DEVICE" ]; then
  DEVICE=$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE")
fi
DEVICE_DATA="$HOME/Library/Developer/CoreSimulator/Devices/$DEVICE/data"

echo "Resetting simulator…"
xcrun simctl shutdown "$DEVICE" 2>/dev/null || true
xcrun simctl erase "$DEVICE"
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b >/dev/null
xcrun simctl status_bar "$DEVICE" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularBars 4

echo "Staging photos…"
SAMPLES="$DEVICE_DATA/Media/DCIM/100APPLE"
for _ in $(seq 60); do
  ls "$SAMPLES"/*.JPG >/dev/null 2>&1 && break
  sleep 1
done
swift "$ROOT/Tools/stage-demo-photos.swift" "$SAMPLES" "$WORK/photos"
xcrun simctl addmedia "$DEVICE" "$WORK"/photos/*.jpg

echo "Building…"
xcodebuild -project "$ROOT/Journey.xcodeproj" -scheme Journey-Demo -derivedDataPath "$DERIVED" \
  -destination "id=$DEVICE" -configuration Debug build-for-testing >/dev/null

run_test() {
  xcodebuild test-without-building -project "$ROOT/Journey.xcodeproj" -scheme Journey-Demo \
    -derivedDataPath "$DERIVED" -destination "id=$DEVICE" \
    -only-testing:"JourneyUITests/DemoWalkthrough/$1" > "$WORK/$1.log" 2>&1
}

now() {
  perl -MTime::HiRes=time -e 'printf "%.3f\n", time'
}

# Prompts are answered before recording so they stay out of the GIF. Photos are
# not granted with simctl: on iOS 26 the prompt appears anyway, and a prompt
# during the recording gets dismissed as "Don't Allow" by XCTest.
echo "Granting permissions…"
xcrun simctl install "$DEVICE" "$DERIVED/Build/Products/Debug-iphonesimulator/Journey.app"
xcrun simctl privacy "$DEVICE" grant location-always "$BUNDLE_ID"
# The first test run on a freshly erased simulator sometimes dies (Mach error -308).
for attempt in 1 2 3; do
  run_test testGrantPermissions && break
  echo "  attempt $attempt failed, retrying…"
done
PHOTOS=$(sqlite3 "$DEVICE_DATA/Library/TCC/TCC.db" \
  "select auth_value from access where service='kTCCServicePhotos' and client='$BUNDLE_ID';")
if [ "$PHOTOS" != "2" ]; then
  echo "Photo access wasn't granted (auth_value '${PHOTOS:-none}'):"
  tail -20 "$WORK/testGrantPermissions.log"
  exit 1
fi

# Recording starts before the test (starting it mid-launch makes the launch time
# out); the walkthrough prints wall-clock markers, and the GIF is trimmed to them
# so the test runner's slow start-up and the teardown stay out.
echo "Recording…"
xcrun simctl io "$DEVICE" recordVideo --codec h264 --force "$WORK/demo.mov" > "$WORK/record.log" 2>&1 &
REC=$!
until grep -q "Recording started" "$WORK/record.log"; do sleep 0.1; done
REC_START=$(now)
TEST_OK=1
run_test testRecordDemo || TEST_OK=0
kill -INT "$REC" 2>/dev/null || true
wait "$REC" 2>/dev/null || true
if [ "$TEST_OK" != "1" ]; then
  echo "The demo test failed:"
  tail -20 "$WORK/testRecordDemo.log"
  exit 1
fi
MARK_START=$(sed -n 's/.*DEMO-START \([0-9.]*\).*/\1/p' "$WORK/testRecordDemo.log" | head -1)
MARK_END=$(sed -n 's/.*DEMO-END \([0-9.]*\).*/\1/p' "$WORK/testRecordDemo.log" | head -1)
if [ -z "$MARK_START" ] || [ -z "$MARK_END" ]; then
  echo "No DEMO-START/DEMO-END markers in the test log."
  exit 1
fi
TRIM_START=$(perl -e "printf '%.2f', $MARK_START - $REC_START")
TRIM_END=$(perl -e "printf '%.2f', $MARK_END - $REC_START")

echo "Encoding…"
swift "$ROOT/Tools/make-gif.swift" "$WORK/demo.mov" "$ROOT/Docs/demo.gif" "$FPS" "$SPEEDUP" "$WIDTH" \
  "$TRIM_START" "$TRIM_END"
echo "Wrote Docs/demo.gif"
if [ "${KEEP_CAPTURE:-0}" = "1" ]; then
  echo "Capture kept at $WORK/demo.mov"
fi
