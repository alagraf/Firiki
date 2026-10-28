#!/bin/bash
# Thesis fork: builds and runs a subset of OpenIntelligenceTests on the simulator, prints the
# results, and stops xcodebuild once both XCTest and Swift Testing have reported (on this machine
# xcodebuild keeps waiting on the test host after the last result).
# Usage: scripts/thesis_run_tests.sh <log-file> [-only-testing:... ...]
set -u
LOG="$1"; shift
DEST="${OPENINTELLIGENCE_SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 18 Pro}"
DD="${OPENINTELLIGENCE_DERIVED_DATA:-/private/tmp/oi-build}"
xcodebuild build-for-testing -scheme OpenIntelligence -destination "$DEST" -derivedDataPath "$DD" > "$LOG.build" 2>&1
if ! grep -q "TEST BUILD SUCCEEDED" "$LOG.build"; then
  grep -E "error:" "$LOG.build" | sort -u | head -40
  echo "** TEST BUILD FAILED ** (see $LOG.build)"
  exit 1
fi
echo "** TEST BUILD SUCCEEDED **"
run_tests() {
  # Stopping xcodebuild can leave the simulator unable to launch the next run ("Invalid
  # connectionUUID"), so every run starts from a shut-down simulator.
  xcrun simctl shutdown all >/dev/null 2>&1
  xcodebuild test-without-building -scheme OpenIntelligence -destination "$DEST" -derivedDataPath "$DD" "$@" > "$LOG" 2>&1 &
  PID=$!
  for _ in $(seq 1 1800); do
    if ! kill -0 $PID 2>/dev/null; then break; fi
    if grep -qE "Test run with [0-9]+ tests? .*(passed|failed)" "$LOG"; then sleep 5; kill $PID 2>/dev/null; break; fi
    sleep 1
  done
  kill $PID 2>/dev/null
  wait $PID 2>/dev/null
}
run_tests "$@"
if grep -q "Failed to prepare device" "$LOG"; then
  echo "(simulator failed to launch; retrying once)"
  sleep 5
  run_tests "$@"
fi
grep -E "Executed [0-9]+ tests, with|Test Case .* failed|error: -\[|✘|Test run with" "$LOG" | cut -c1-400 | sort -u
