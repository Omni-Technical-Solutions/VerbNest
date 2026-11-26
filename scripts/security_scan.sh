#!/usr/bin/env bash
# The security scan that every release must pass (docs/release/checklist.md,
# phase-commit step 8c). It runs the same checks as CI, locally, so a finding
# is fixed before anything is tagged, uploaded or published:
#
#   1. secrets in the git history (gitleaks, like the `secrets` CI job);
#   2. known advisories in pubspec.lock and in the Rust crates behind the
#      script engine (osv-scanner with osv-scanner.toml, like audit.yml);
#   3. that no reviewed exception in osv-scanner.toml has expired or expires
#      within 30 days (an exception that lapses mid-release turns CI red);
#   4. that the latest `ci.yml` run on main is green.
#
# A missing tool is a failure, not a skip: a scan that did not run proves
# nothing. Exit 0 only when every check passes.
#
# Usage: scripts/security_scan.sh
set -u
cd "$(git rev-parse --show-toplevel)"

fail=0
step() { printf '\n== %s\n' "$1"; }
bad() { echo "FAIL: $1"; fail=1; }

step "1. secrets (gitleaks)"
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks git --redact --no-banner || bad "gitleaks found a secret (rotate it, then remove it from the history)"
else
  bad "gitleaks is not installed (brew install gitleaks)"
fi

step "2. known advisories (osv-scanner)"
if command -v osv-scanner >/dev/null 2>&1; then
  cargo_lock=$(ls "$HOME"/.pub-cache/hosted/pub.dev/fjs-*/libfjs/Cargo.lock 2>/dev/null | head -n 1)
  args=(scan source --config=osv-scanner.toml -L pubspec.lock)
  if [ -n "$cargo_lock" ]; then
    args+=(-L "$cargo_lock")
  else
    echo "note: no fjs Cargo.lock in the pub cache (run flutter pub get); scanning pubspec.lock only"
  fi
  osv-scanner "${args[@]}" || bad "osv-scanner found an unreviewed advisory: update the package, or add a reviewed, dated exception to osv-scanner.toml with its reason"
else
  bad "osv-scanner is not installed (brew install osv-scanner)"
fi

step "3. reviewed exceptions that are about to expire"
python3 - <<'PY' || fail=1
import datetime, re, sys
limit = datetime.date.today() + datetime.timedelta(days=30)
late = []
for m in re.finditer(r'id = "([^"]+)"\s*\nignoreUntil = (\d{4}-\d{2}-\d{2})', open("osv-scanner.toml").read()):
    if datetime.date.fromisoformat(m.group(2)) <= limit:
        late.append((m.group(1), m.group(2)))
for i, d in late:
    print(f"  {i} expires {d}")
if late:
    print("FAIL: re-check these against a new release of the package and extend only with a fresh reason")
    sys.exit(1)
print("  none expire within 30 days")
PY

step "4. CI on main"
if command -v gh >/dev/null 2>&1; then
  run=$(gh run list -R Omni-Technical-Solutions/VerbNest --workflow ci.yml --branch main --limit 1 --json conclusion,status,displayTitle -q '.[0]|"\(.status) \(.conclusion) \(.displayTitle)"' 2>/dev/null || true)
  echo "  latest: ${run:-unknown}"
  case "$run" in
    "completed success"*) ;;
    *) bad "the latest ci.yml run on main is not green" ;;
  esac
else
  bad "gh is not installed, cannot read the CI result"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "security_scan: passed"
else
  echo "security_scan: FAILED. Fix each finding above, commit the fix, run this again."
fi
exit "$fail"
