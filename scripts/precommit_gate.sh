#!/usr/bin/env bash
# The mechanical part of the quality, complexity, efficiency and performance
# checks: runs before every commit (installed as .git/hooks/pre-commit by
# scripts/install_hooks.sh). Docs-only commits pass without running anything.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

staged=$(git diff --cached --name-only --diff-filter=ACMR)
code=$(printf '%s\n' "$staged" | grep -E '\.(dart|py|sh|swift|java|kt|c|cc|cpp|h|yaml)$|pubspec' || true)

# A release bookkeeping commit (BUILD_NUMBER, and a pubspec whose only change is
# its `version:` line) changes no code: it must not cost a full test run.
only_version_line() {
  [ -z "$(git diff --cached -U0 -- "$1" | grep -E '^[+-][^+-]' | grep -vE '^[+-]version: ' || true)" ]
}
kept=""
for f in $code; do
  case "$f" in
    */pubspec.yaml | pubspec.yaml) only_version_line "$f" && continue ;;
  esac
  kept="$kept$f
"
done
code=$(printf '%s' "$kept" | sed '/^$/d')
if [ -z "$code" ]; then
  echo "precommit_gate: no code staged, nothing to check"
  exit 0
fi

echo "precommit_gate: complexity gate"
python3 scripts/complexity_report.py --check

dirs=$(printf '%s\n' "$staged" | sed -nE 's#^(packages/[^/]+|apps/[^/]+|test_server)/.*#\1#p' | sort -u)
for d in $dirs; do
  [ -f "$d/pubspec.yaml" ] || continue
  if grep -q '^  flutter:' "$d/pubspec.yaml"; then tool=flutter; else tool=dart; fi
  echo "precommit_gate: $tool analyze $d"
  (cd "$d" && $tool analyze --fatal-infos)
  if [ -n "$(find "$d/test" -name '*_test.dart' 2>/dev/null | head -1)" ]; then
    echo "precommit_gate: $tool test $d"
    (cd "$d" && $tool test -r failures-only)
  fi
done
echo "precommit_gate: passed"
