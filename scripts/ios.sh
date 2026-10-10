#!/usr/bin/env bash
# Reproducible iOS build/test entry point, used by humans and CI alike.
#
#   scripts/ios.sh build   # compile the app AND the widget extension
#   scripts/ios.sh test    # run the XCTest unit tests (UnpluggedTests)
#   scripts/ios.sh all     # build, then test
#
# Environment (all optional):
#   IOS_SIM_UDID   simulator to use (default: first available iPhone)
#   IOS_DERIVED    derived-data path (default: ios/build/DerivedData)
#
# Exit codes: 0 ok, 1 build/test failure, 2 Xcode missing, 3 iOS SDK too old, 4 no iPhone simulator.
# Unavailable tooling is reported as a failure on purpose: a check that cannot run must never look like a pass.
set -euo pipefail

cd "$(dirname "$0")/../ios"
MIN_SDK_MAJOR=26   # Liquid Glass APIs (glassEffect) need the iOS 26 SDK
DERIVED="${IOS_DERIVED:-build/DerivedData}"
mkdir -p build

die() { echo "ios.sh: $2" >&2; exit "$1"; }

command -v xcodebuild >/dev/null 2>&1 || die 2 "xcodebuild not found. Install Xcode ${MIN_SDK_MAJOR}+ and run: sudo xcode-select -s /Applications/Xcode.app"

sdk="$(xcodebuild -showsdks 2>/dev/null | sed -n 's/.*-sdk iphonesimulator\([0-9][0-9.]*\).*/\1/p' | head -1)"
[ -n "$sdk" ] || die 3 "No iOS Simulator SDK found. Install the iOS platform in Xcode > Settings > Components."
[ "${sdk%%.*}" -ge "$MIN_SDK_MAJOR" ] || die 3 "iOS Simulator SDK $sdk found, but ${MIN_SDK_MAJOR}.0 or newer is required. Select a newer Xcode."

udid="${IOS_SIM_UDID:-}"
if [ -z "$udid" ]; then
  udid="$(xcrun simctl list devices available | sed -n 's/^ *iPhone[^(]*(\([0-9A-F-]\{36\}\)).*/\1/p' | head -1)"
fi
[ -n "$udid" ] || die 4 "No available iPhone simulator. Create one in Xcode > Window > Devices and Simulators, or set IOS_SIM_UDID."

echo "== $(xcodebuild -version | tr '\n' ' ')| iOS SDK $sdk | simulator $udid"

# CODE_SIGNING_ALLOWED=NO: simulator builds need no signing identity or Apple ID team.
common=(-project Unplugged.xcodeproj -destination "id=$udid" -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO)

run_build() {
  echo "== Build app (also builds and embeds the widget extension)"
  xcodebuild build "${common[@]}" -scheme Unplugged | tee build/build-app.log | tail -5
  echo "== Build widget extension on its own"
  xcodebuild build "${common[@]}" -scheme UnpluggedWidgets | tee build/build-widget.log | tail -5
}

run_test() {
  echo "== Unit tests"
  rm -rf build/Unplugged.xcresult
  xcodebuild test "${common[@]}" -scheme Unplugged -resultBundlePath build/Unplugged.xcresult | tee build/test.log | tail -25
  grep -E "Executed [0-9]+ tests?" build/test.log | tail -1
}

case "${1:-all}" in
  build) run_build ;;
  test)  run_test ;;
  all)   run_build; run_test ;;
  *)     die 1 "usage: scripts/ios.sh [build|test|all]" ;;
esac
echo "== OK"
