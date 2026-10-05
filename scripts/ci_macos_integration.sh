#!/usr/bin/env bash
# Runs each macOS integration test in its own app launch. On hosted runners
# a launch that follows another one can fail with "log reader stopped
# unexpectedly", so each file gets a clean process table and one retry.
set -u
cd "$(dirname "$0")/../apps/postit_app"
status=0
for f in integration_test/*_test.dart; do
  ok=0
  for attempt in 1 2 3; do
    pkill -x PostIt 2>/dev/null || true
    sleep 3
    echo "== $f (attempt $attempt)"
    if flutter test "$f" -d macos; then ok=1; break; fi
  done
  if [ "$ok" -ne 1 ]; then echo "FAILED: $f"; status=1; fi
done
pkill -x PostIt 2>/dev/null || true
exit $status
