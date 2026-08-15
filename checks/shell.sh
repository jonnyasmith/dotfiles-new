#!/usr/bin/env bash
# Parse and lint every shell this repo would install or run, on every machine.
#
# Works on the rendered output, not the templates: a `.tmpl` is not valid shell
# until Tera has run, and the branch that breaks is usually the one this machine
# never takes.
set -uo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"

# Rendering costs a few seconds, so `check` does it once and hands the
# directory down. Run on its own, this renders its own copy.
work="${1:-}"
if [ -z "$work" ]; then
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
    "$repo/checks/render.sh" "$work" >/dev/null || { echo "  ! render failed"; exit 1; }
fi

have_sc=1
command -v shellcheck >/dev/null 2>&1 || {
    have_sc=0
    echo "  ! shellcheck missing — install it (it is in [tools])"
}
have_zsh=1
command -v zsh >/dev/null 2>&1 || {
    have_zsh=0
    echo "  ! zsh missing — install it"
}

bad=0
n_sh=0
n_zsh=0

for machine in "$work"/*/; do
    id="$(basename "$machine")"

    # Shebang, not extension: it is what the kernel reads, and it is the only
    # thing that distinguishes a bash target from an sh one.
    while IFS= read -r f; do
        [ -L "$f" ] && continue
        case "$(head -1 "$f")" in
        '#!'*sh) ;;
        *) continue ;;
        esac
        n_sh=$((n_sh + 1))
        bash -n "$f" || { echo "  ! $id: ${f#"$machine"} does not parse"; bad=1; }
        if [ "$have_sc" -eq 1 ]; then
            shellcheck -S warning "$f" || bad=1
        fi
    done < <(find "$machine" -type f ! -name chezmoi.toml)

    # No shebang to key on, and zsh syntax bash would reject.
    if [ "$have_zsh" -eq 1 ]; then
        for rel in .zshrc .zshenv .zprofile .config/zsh/aliases.zsh .config/zsh/os.zsh; do
            f="$machine/files/$rel"
            [ -f "$f" ] || continue
            n_zsh=$((n_zsh + 1))
            zsh -n "$f" || { echo "  ! $id: $rel does not parse"; bad=1; }
        done
    fi
done

# The check suite lints itself; nothing else would.
if [ "$have_sc" -eq 1 ]; then
    shellcheck -S warning "$repo"/checks/*.sh || bad=1
fi

[ "$bad" -eq 0 ] && echo "  . $n_sh shell file(s) and $n_zsh zsh file(s) parse"
exit "$bad"
