#!/usr/bin/env bash
# Run the test suite on a physically connected iPhone.
#
# Nothing in this project had ever run on real hardware before 2026-08-18, and the reason was not
# effort. `FirikiEngine.framework` is built with an absolute macOS install name,
# `/Library/Frameworks/FirikiEngine.framework/FirikiEngine`, and is not embedded
# anywhere in the app. The app itself does not link it, so the app runs fine. The test bundle does
# link it, so on device it fails at load with:
#
#     Library not loaded: /Library/Frameworks/FirikiEngine.framework/FirikiEngine
#
# In the simulator that path happens to resolve, which is why 238 tests pass there and zero ran here.
#
# The real fix is the framework's DYLIB_INSTALL_NAME_BASE in project.pbxproj, which is a
# hard-boundary file. This script is the workaround that needs no project change: the test bundle
# already carries `@loader_path/Frameworks` in its rpath, so putting the framework there and
# rewriting both install names to @rpath is sufficient.
#
# THE TRAP, which cost a cycle: re-signing the .app without `--entitlements` strips
# `application-identifier`, and installation then fails with
# `_validateApplicationIdentifierForNewBundleSigningInfo` and the unhelpful message "Please try
# again later". The entitlements must be extracted from the freshly built bundle and passed back.
set -euo pipefail

DEV=/Applications/Xcode-beta.app/Contents/Developer
DD="${DD:-/private/tmp/oi-dev}"
SRC="${SRC:-/private/tmp/oi-src}"
ONLY="${ONLY:-}"          # e.g. ONLY=FirikiTests/EmbeddingProviderAgreementTests
SIGN_ID="${SIGN_ID:-Apple Development: Gunnar Hostetler (3YEN53ZQDU)}"

# xcodebuild wants the CoreDevice UUID; xctrace wants the hardware UDID. They are different values
# for the same phone, and using the wrong one gives "No devices found matching".
UDID="${UDID:-$(DEVELOPER_DIR=$DEV xcrun devicectl list devices 2>/dev/null \
  | awk '/connected/ && /iPhone/ {print $(NF-3); exit}')}"

if [ -z "$UDID" ]; then
  echo "error: no connected iPhone. Plug in over USB and unlock it." >&2
  echo "Wireless does not work: the RSD tunnel fails with 'Failed to allocate RSD device'" >&2
  echo "during enablePersonalizedDDI. Transport must read 'wired' in:" >&2
  echo "  xcrun devicectl device info details --device <uuid> | grep Transport" >&2
  exit 1
fi
echo "device: $UDID"

echo "==> syncing source out of iCloud"
rsync -a --exclude 'BenchmarkRuns/' --exclude '.simulator-smoke.nosync/' --exclude 'Benchmarks/run/' \
  "$(git rev-parse --show-toplevel)/" "$SRC/"

echo "==> build-for-testing"
cd "$SRC"
DEVELOPER_DIR=$DEV xcodebuild build-for-testing \
  -scheme Firiki \
  -destination "platform=iOS,id=$UDID" \
  -derivedDataPath "$DD" \
  -allowProvisioningUpdates -quiet

PROD="$DD/Build/Products/Debug-iphoneos"
APP="$PROD/Firiki.app"
XC="$APP/PlugIns/FirikiTests.xctest"
FW=FirikiEngine.framework
RPATH="@rpath/FirikiEngine.framework/FirikiEngine"
ABS="/Library/Frameworks/FirikiEngine.framework/FirikiEngine"

echo "==> capturing entitlements before they can be lost"
codesign -d --entitlements :- "$APP" > /private/tmp/oi-app-ent.plist 2>/dev/null
APPEX="$APP/PlugIns/FirikiLiveActivities.appex"
[ -d "$APPEX" ] && codesign -d --entitlements :- "$APPEX" > /private/tmp/oi-appex-ent.plist 2>/dev/null || true

echo "==> embedding the engine framework into the test bundle"
mkdir -p "$XC/Frameworks"
rm -rf "$XC/Frameworks/$FW"
cp -R "$PROD/$FW" "$XC/Frameworks/"
install_name_tool -id "$RPATH" "$XC/Frameworks/$FW/FirikiEngine" 2>/dev/null
install_name_tool -change "$ABS" "$RPATH" "$XC/FirikiTests" 2>/dev/null

echo "==> re-signing, innermost first, entitlements preserved"
codesign -f -s "$SIGN_ID" "$XC/Frameworks/$FW" >/dev/null 2>&1
codesign -f -s "$SIGN_ID" "$XC" >/dev/null 2>&1
[ -d "$APPEX" ] && codesign -f -s "$SIGN_ID" --entitlements /private/tmp/oi-appex-ent.plist "$APPEX" >/dev/null 2>&1 || true
codesign -f -s "$SIGN_ID" --entitlements /private/tmp/oi-app-ent.plist "$APP" >/dev/null 2>&1
codesign -v "$APP" || { echo "error: signature invalid after patching" >&2; exit 1; }

echo "==> running on device"
ARGS=(-scheme Firiki -destination "platform=iOS,id=$UDID" -derivedDataPath "$DD")
[ -n "$ONLY" ] && ARGS+=(-only-testing:"$ONLY")
DEVELOPER_DIR=$DEV xcodebuild test-without-building "${ARGS[@]}"
