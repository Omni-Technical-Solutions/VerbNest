#!/usr/bin/env bash
# Runs the App Store review walk-through on a PHYSICAL iPhone and records the
# phone's screen from before the app starts until the last check has run.
#
#   scripts/app_review_recording.sh [device-id]
#
# The phone must be connected by cable, unlocked, trusted, and set to never
# auto-lock for the duration (Settings > Display & Brightness > Auto-Lock).
# Result: ~/Downloads/VerbNest-<version>+<build>-app-review.mp4 and a text log
# with the time of each step (APP-REVIEW lines) beside it.
#
# Environment:
#   MODE=--profile (default) | --debug   build mode of the app under test
#   WARMUP=0                             skip the unrecorded first run that
#                                        builds and installs the app
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
version="$(tr -d '[:space:]' < VERSION)"
build="$(tr -d '[:space:]' < BUILD_NUMBER)"
mode="${MODE:---profile}"
out_dir="${OUT_DIR:-$HOME/Downloads}"
base="$out_dir/VerbNest-${version}+${build}-app-review"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

device="${1:-}"
if [ -z "$device" ]; then
  device="$(cd apps/verbnest_app && flutter devices --machine 2>/dev/null |
    python3 -c 'import json,sys
for d in json.load(sys.stdin):
    if d.get("targetPlatform")=="ios" and not d.get("emulator") and d.get("sdk","").startswith("iOS"):
        print(d["id"]); break')"
fi
[ -n "$device" ] || { echo "No physical iPhone found: connect it, unlock it, tap Trust." >&2; exit 1; }
echo "Device: $device"

recorder="${TMPDIR:-/tmp}/ios_screen_record"
if [ ! -x "$recorder" ] || [ scripts/ios_screen_record.swift -nt "$recorder" ]; then
  swiftc -O scripts/ios_screen_record.swift -o "$recorder"
fi

drive() {
  (cd apps/verbnest_app && export PATH="$HOME/.cargo/bin:$PATH" &&
    flutter drive --driver=test_driver/integration_test.dart \
      --target=integration_test/app_review_device_test.dart \
      -d "$device" "$mode")
}

if [ "${WARMUP:-1}" = "1" ]; then
  echo "Warm-up run (builds and installs the app; not recorded)..."
  drive > "$work/warmup.log" 2>&1 || { tail -40 "$work/warmup.log"; echo "Warm-up failed." >&2; exit 1; }
fi

echo "Recording (the recorder starts the walk-through itself)..."
status=0
"$recorder" "$work/raw.mov" -- bash -c "$(declare -f drive); device='$device'; mode='$mode'; drive > '$work/run.log' 2>&1" \
  > "$work/recorder.log" 2>&1 || status=$?
cat "$work/recorder.log"
[ -s "$work/raw.mov" ] || { echo "No recording was made." >&2; exit 1; }

# The build and install before the app opens are not part of the story: start
# the video a few seconds before the app launches (the first APP-REVIEW line).
first_frame="$(sed -n 's/^first frame .* at //p' "$work/recorder.log" | head -1)"
first_step="$(grep -m1 'APP-REVIEW' "$work/run.log" | sed -E 's/.*APP-REVIEW ([^ ]+) .*/\1/')"
start=0
if [ -n "$first_frame" ] && [ -n "$first_step" ]; then
  start="$(python3 - "$first_frame" "$first_step" <<'PY'
import sys
from datetime import datetime
a = datetime.fromisoformat(sys.argv[1]); b = datetime.fromisoformat(sys.argv[2])
print(max(0.0, (b - a).total_seconds() - 4))
PY
)"
fi
echo "Video starts $start s into the capture (4 s before the app opens)."

# The App Store accepts H.264 in an mp4; the phone's screen is 9:19.5.
ffmpeg -y -loglevel error -ss "$start" -i "$work/raw.mov" -c:v libx264 -preset slow -crf 20 \
  -pix_fmt yuv420p -movflags +faststart -an "$base.mp4"
grep "APP-REVIEW" "$work/run.log" > "$base.log" || true
echo "--- steps"; cat "$base.log"
if [ "$status" -ne 0 ]; then
  tail -40 "$work/run.log"
  echo "The walk-through FAILED (exit $status). Recording kept at $base.mp4" >&2
  exit "$status"
fi
echo "Recording: $base.mp4"
