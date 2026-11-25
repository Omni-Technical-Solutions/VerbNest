#!/usr/bin/env bash
# Records that the review skills were satisfied for the currently staged diff.
# Any later change to the staged content invalidates it (see
# .claude/hooks/commit-gate.sh). Runs the mechanical gate first.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
scripts/precommit_gate.sh
git diff --cached | shasum -a 256 | cut -d' ' -f1 > .claude/.reviewed
echo "mark_reviewed: recorded for the staged diff"
