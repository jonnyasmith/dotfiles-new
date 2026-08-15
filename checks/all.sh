#!/usr/bin/env bash
# Every check, in one render.
#
# The list lives here rather than in mise's `depends`, so the render is paid for
# once and each check still runs even after an earlier one fails — one CI run
# should report every problem, not the first.
set -uo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failed=""
run() {
    local label="$1"
    shift
    echo "==> $label"
    "$@" || failed="$failed $label"
}

echo "==> render"
if ! "$repo/checks/render.sh" "$work"; then
    echo "  ! nothing else can run until the templates render"
    exit 1
fi

run shell "$repo/checks/shell.sh" "$work"
run pwsh "$repo/checks/pwsh.sh" "$work"
run config "$repo/checks/config.sh" "$work"
run packages python3 "$repo/checks/packages.py" "$repo"
run comments python3 "$repo/checks/comments.py" "$repo"
run dconf python3 "$repo/checks/dconf.py" "$repo"

if [ -n "$failed" ]; then
    echo "failed:$failed"
    exit 1
fi
echo "all checks passed"
