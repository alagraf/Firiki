#!/bin/bash
# Runs the thesis unit suite (iOS Simulator) and, when DEMO_SMOKE=1, the README smoke UI test in the
# iPhone Simulator (the UI-test target doesn't build for macOS).
# Usage:
#   scripts/demo_check.sh
#   DEMO_SMOKE=1 scripts/demo_check.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

UNIT_LOG="${DEMO_CHECK_UNIT_LOG:-/private/tmp/firiki-demo-check-unit.log}"
echo "== Running FirikiTests unit suite, with the demo PDF imports (about 15 minutes) =="
TEST_RUNNER_OI_DEMO_PDFS=1 ./scripts/thesis_run_tests.sh "$UNIT_LOG"

if grep -qE "with [1-9][0-9]* failure" "$UNIT_LOG" || grep -q "✘ Test" "$UNIT_LOG"; then
  echo "Unit suite reported failures (see $UNIT_LOG)"
  exit 1
fi

if [ "${DEMO_SMOKE:-0}" = "1" ]; then
  SMOKE_LOG="${DEMO_CHECK_SMOKE_LOG:-/private/tmp/firiki-demo-smoke.log}"
  echo "== Running DemoSmokeUITests in the iPhone Simulator =="
  TEST_RUNNER_OI_DEMO_SMOKE=1 xcodebuild test \
    -scheme FirikiUITests \
    -destination "${FIRIKI_SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 18 Pro}" \
    -derivedDataPath "${FIRIKI_UI_DERIVED_DATA:-/private/tmp/oi-ui-sim}" \
    -only-testing:FirikiUITests/DemoSmokeUITests \
    > "$SMOKE_LOG" 2>&1
  grep -E "Test Case|Executed [0-9]+ tests|TEST " "$SMOKE_LOG" | tail -n 20
else
  echo "== Skipping DemoSmokeUITests (pass DEMO_SMOKE=1 with the library imported in the Simulator) =="
fi
