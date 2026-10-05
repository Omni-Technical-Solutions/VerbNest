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
cd "$(dirname "$0")/../apps/postit_app"
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
if [ "$device" = linux ]; then runner=(xvfb-run -a); fi

status=0
for f in "${files[@]}"; do
  ok=0
  for attempt in 1 2 3; do
    kill_app
    sleep 3
    echo "== $f (attempt $attempt)"
    if ${runner[@]+"${runner[@]}"} flutter test "$f" -d "$device"; then ok=1; break; fi
  done
  if [ "$ok" -ne 1 ]; then echo "FAILED: $f"; status=1; fi
done
kill_app
exit $status
