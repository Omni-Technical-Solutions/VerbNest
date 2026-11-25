#!/usr/bin/env bash
# Installs the git pre-commit hook that runs scripts/precommit_gate.sh.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
hook="$root/.git/hooks/pre-commit"
printf '#!/usr/bin/env bash\nexec "$(git rev-parse --show-toplevel)/scripts/precommit_gate.sh"\n' > "$hook"
chmod +x "$hook" "$root/scripts/precommit_gate.sh"
echo "installed $hook"
