#!/usr/bin/env bash
# Parse the rendered PowerShell with PowerShell's own parser.
#
# Split from check:shell because pwsh is not on a Linux CI runner by default and
# a missing parser must read as "skipped", never as "clean".
set -uo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v pwsh >/dev/null 2>&1; then
    echo "  . pwsh not installed, skipped"
    exit 0
fi

WORK="${1:-}"
export WORK
if [ -z "$WORK" ]; then
    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT
    "$repo/checks/render.sh" "$WORK" >/dev/null || { echo "  ! render failed"; exit 1; }
fi

# ParseFile reports every syntax error in the file, which Invoke-Expression and
# `-Command` would not: neither can parse a script without also running it.
pwsh -NoProfile -Command '
$bad = 0; $n = 0
foreach ($f in Get-ChildItem -Recurse -File -Filter *.ps1 $env:WORK) {
    $n++
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $f.FullName, [ref]$null, [ref]$errors) | Out-Null
    foreach ($e in $errors) {
        Write-Host "  ! $($f.Name):$($e.Extent.StartLineNumber) $($e.Message)"
        $bad = 1
    }
}
if ($bad -eq 0) { Write-Host "  . $n PowerShell file(s) parse" }
exit $bad
' 2>&1
