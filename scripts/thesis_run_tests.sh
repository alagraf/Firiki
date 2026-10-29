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
  # connectionUUID"), and a shutdown can stick in "Shutting Down", where xcodebuild waits for
  # ever. Every run starts from a device that is booted and has finished booting.
  local name="${DEST##*name=}"
  if xcrun simctl list devices | grep -F "$name (" | grep -q "Shutting Down"; then
    killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1
    sleep 3
  fi
  # A runner that was stopped can leave the next launch waiting for ever with the device still
  # "Booted" (2026-10-29, four times; shutting the device down alone did not clear it, restarting
  # the simulator service did): every run starts from a fresh service and boot.
  # The Mac's own testmanagerd can be the stuck end: it is restarted by launchd when needed.
  xcrun simctl shutdown all >/dev/null 2>&1
  killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1
  pkill -x -u "$(id -u)" testmanagerd >/dev/null 2>&1
  sleep 5
  xcrun simctl bootstatus "$name" -b >/dev/null 2>&1
  # Launching the app right after the boot finished failed with "No such process" (2026-10-29).
  sleep 20
  xcodebuild test-without-building -scheme OpenIntelligence -destination "$DEST" -derivedDataPath "$DD" "$@" > "$LOG" 2>&1 &
  PID=$!
  # OI_TEST_TIMEOUT_SECONDS: the longest a run may take (default 30 min; a full-corpus evaluation needs more).
  for i in $(seq 1 "${OI_TEST_TIMEOUT_SECONDS:-1800}"); do
    if ! kill -0 $PID 2>/dev/null; then break; fi
    # No test has started 5 minutes after launch: the runner is stuck, stop and let the retry run.
    if [ "$i" -eq 300 ] && ! grep -qE "Test (Case|Suite)|◇ Test|Test run" "$LOG"; then
      echo "Test runner hung: no test started in 5 minutes" >> "$LOG"; kill $PID 2>/dev/null; break
    fi
    if grep -qE "Test run with [0-9]+ tests? .*(passed|failed)" "$LOG"; then sleep 5; kill $PID 2>/dev/null; break; fi
    sleep 1
  done
  kill $PID 2>/dev/null
  wait $PID 2>/dev/null
}
run_tests "$@"
if grep -qiE "Failed to prepare device|test runner hung" "$LOG"; then
  echo "(simulator failed to launch; restarting the simulator service and retrying once)"
  # The Mac's own testmanagerd can be the stuck end: it is restarted by launchd when needed.
  xcrun simctl shutdown all >/dev/null 2>&1
  killall -9 com.apple.CoreSimulator.CoreSimulatorService >/dev/null 2>&1
  pkill -x -u "$(id -u)" testmanagerd >/dev/null 2>&1
  sleep 5
  run_tests "$@"
fi
grep -E "Executed [0-9]+ tests, with|Test Case .* failed|error: -\[|✘|Test run with" "$LOG" | cut -c1-400 | sort -u
