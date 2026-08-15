#!/usr/bin/env bash
# Render the whole source state, once per machine the repo claims to support.
#
# Every other check reads this output rather than the templates, because a
# template is not shell, TOML or JSON until Tera has run — and the interesting
# bugs live in the branches this machine would never take.
#
# Writes $1/<family>-<isWSL>-<work>/{files,scripts}. `files` is the target state
# chezmoi would apply, taken from `chezmoi archive` so nothing is written
# outside the output directory. `scripts` is .chezmoiscripts rendered one file
# at a time, since archive excludes them.
set -euo pipefail

out="${1:?usage: render.sh OUTDIR}"
repo="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$out"

command -v chezmoi >/dev/null 2>&1 || { echo "  ! chezmoi is required"; exit 1; }

# family isWSL work. darwin appears twice so the work-only git identity, ssh
# config and worktree wrappers are rendered by something.
COMBOS=(
    "darwin false false"
    "darwin false true"
    "debian false false"
    "debian true false"
    "fedora false false"
    "arch false false"
    "windows false false"
)

for combo in "${COMBOS[@]}"; do
    read -r family wsl work <<<"$combo"
    dir="$out/$family-$wsl-$work"
    mkdir -p "$dir/files" "$dir/scripts"

    cfg="$dir/chezmoi.toml"
    cat >"$cfg" <<EOF
sourceDir = "$repo/home"
[data]
    family = "$family"
    isWSL = $wsl
    work = $work
    workOrgs = "$([ "$work" = true ] && echo "example-org")"
    workEmail = "$([ "$work" = true ] && echo "work@example.com")"
EOF

    # --exclude=externals keeps this offline; --exclude=scripts because they are
    # rendered individually below. --format=tar is not the default and is not
    # optional: chezmoi gzips otherwise, which GNU tar refuses to autodetect.
    chezmoi archive --format=tar --config "$cfg" --source "$repo/home" \
        --exclude=scripts,externals 2>/dev/null |
        tar -xm -C "$dir/files"

    for f in "$repo"/home/.chezmoiscripts/*.tmpl; do
        name="$(basename "$f" .tmpl)"
        chezmoi execute-template --config "$cfg" --source "$repo/home" \
            <"$f" >"$dir/scripts/$name"
        # A script gated off for this machine renders to nothing. chezmoi skips
        # an empty script; so does everything downstream.
        [ -s "$dir/scripts/$name" ] || rm -f "$dir/scripts/$name"
    done
done

echo "  . rendered ${#COMBOS[@]} machine(s) into $out"
