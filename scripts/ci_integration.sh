#!/usr/bin/env bash
# Usage: ci_integration.sh <device> <process-name|-> [file...]
# Runs each integration test in its own app launch. The desktop runners keep
# the app (or its single-instance handle) alive after a test file ends, so
# the next launch cannot start ("log reader stopped unexpectedly"). Each file
# therefore gets the previous process killed first, plus up to three tries.
set -u
device=$1
proc=$2
shift 2
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here/../apps/verbnest_app"
files=("$@")
if [ ${#files[@]} -eq 0 ]; then files=(integration_test/*_test.dart); fi

kill_app() {
  # "-" means a mobile target whose app the test runner reinstalls itself.
  if [ "$proc" = "-" ]; then return; fi
  case "$device" in
    windows) taskkill //F //IM "$proc.exe" >/dev/null 2>&1 || true ;;
    *) pkill -x "$proc" 2>/dev/null || true ;;
  esac
}

runner=()
# Linux: a display, and a D-Bus session with an unlocked keyring (see
# ci_linux_session.sh): without a secret service the app exits at its vault check.
if [ "$device" = linux ]; then
  runner=(dbus-run-session -- "$here/ci_linux_session.sh" xvfb-run -a)
fi

status=0
for f in "${files[@]}"; do
  ok=0
  for attempt in 1 2 3; do
    kill_app
    sleep 3
    echo "== $f (attempt $attempt)"
    # The expanded reporter, not the GitHub one that Flutter picks inside
    # Actions: with Flutter 3.50 the GitHub reporter counted the device tests as
    # "0 tests passed. No tests were found." and failed a passing run.
    if ${runner[@]+"${runner[@]}"} flutter test "$f" -d "$device" --reporter expanded; then ok=1; break; fi
  done
  if [ "$ok" -ne 1 ]; then
    echo "FAILED: $f"
    status=1
    # The expanded reporter hides why the app process died; one more run with
    # the verbose log shows the embedder's own output (its tail is enough).
    kill_app
    sleep 3
    echo "== $f (diagnostic run, verbose)"
    ${runner[@]+"${runner[@]}"} flutter test "$f" -d "$device" --reporter expanded -v 2>&1 | tail -n 60 || true
    if [ "$device" = linux ]; then
      # The test harness hides the app's own output. Run the built app by
      # itself under the same display and show what it prints and why it ends.
      echo "== linux diagnostics: HOME=$HOME XDG_DOCUMENTS=$(xdg-user-dir DOCUMENTS 2>&1) df:"
      df -h "$HOME" /tmp 2>&1 | tail -n 3
      echo "== linux diagnostics: step-by-step probe (the last DIAG line printed is where the app ends)"
      ${runner[@]+"${runner[@]}"} flutter test integration_test/linux_diag_test.dart -d linux --reporter expanded 2>&1 | grep -E "DIAG|Some tests failed|All tests passed|did not complete" || true
      bundle=build/linux/x64/debug/bundle/verbnest_app
      if [ -x "$bundle" ]; then
        echo "== linux diagnostics: ldd (missing libraries)"
        ldd "$bundle" 2>&1 | grep -i "not found" || echo "none missing"
        echo "== linux diagnostics: the app on its own for 10 s"
        ( ulimit -c 0; timeout 10 xvfb-run -a "$bundle" 2>&1 | tail -n 40; echo "exit ${PIPESTATUS[0]}" ) || true
      fi
    fi
  fi
done
kill_app
exit $status
