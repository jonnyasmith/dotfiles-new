#!/usr/bin/env bash
# Render if needed, then assert the invariants in config.py.
#
# Exists only so `mise run check:config` and `checks/all.sh` reach the same
# code: the first has no rendered output to hand over, the second does.
set -uo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"

work="${1:-}"
if [ -z "$work" ]; then
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
    "$repo/checks/render.sh" "$work" >/dev/null || { echo "  ! render failed"; exit 1; }
fi

python3 "$repo/checks/config.py" "$work"
