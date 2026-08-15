#!/usr/bin/env python3
"""Cap the length of any single comment paragraph.

An unbroken wall of prose is a sign the explanation outgrew the file: it belongs
in docs/, where it can be read without opening the code. The budget is a static
check rather than a convention so it holds without anyone remembering it.

A comment line with nothing on it but the token ends a paragraph, exactly as a
blank line does. That is the house style for a multi-part header here, and a
header broken into labelled parts is what the budget is asking for.

Anything genuinely irreducible carries `comment-budget-skip: <reason>` on the
paragraph's first line.
"""

import pathlib
import subprocess
import sys

MAX = 9
WAIVER = "comment-budget-skip:"

# Filename or extension -> line-comment token. Anything absent is not measured.
# Markdown is out of scope: `#` is a heading there, and prose is what docs/ is
# for. chezmoi's own attribute prefixes are stripped before the lookup, so
# `private_dot_zshrc` is measured as `.zshrc`.
BY_NAME = {
    ".chezmoiignore": "#", ".chezmoiroot": "#", ".gitignore": "#",
    ".zprofile": "#", ".zshenv": "#", ".zshrc": "#", "config": "#",
    "htoprc": "#", "ignore": "#",
}
BY_EXT = {
    ".conf": "#", ".dconf": "#", ".ps1": "#", ".py": "#", ".sh": "#",
    ".tmpl": "#", ".toml": "#", ".txt": "#", ".ts": "//", ".yml": "#",
    ".zsh": "#",
}

# Vendored or tool-written, so not ours to measure. The cosmic tree stays
# byte-comparable to what the desktop writes; agent.toml opens with thirty lines
# of 1Password's own generated header, which cannot carry a waiver.
SKIP = (
    "home/dot_config/1Password/ssh/agent.toml",
    "home/dot_config/btop/btop.conf",
    "home/dot_config/cosmic/",
    "home/dot_config/gh/",
    "home/dot_config/herdr/config.toml",
    "home/dot_config/nvim/",
)

# chezmoi's source-state attributes, longest first so `private_dot_` does not
# match as `private_` and leave `dot_` behind.
PREFIXES = ("encrypted_", "executable_", "private_", "readonly_", "symlink_",
            "empty_", "dot_")


def target_name(name: str) -> str:
    while True:
        for p in PREFIXES:
            if name.startswith(p):
                name = ("." + name[len(p):]) if p == "dot_" else name[len(p):]
                break
        else:
            return name.removesuffix(".tmpl") if name.endswith(".tmpl") else name


def main(repo: pathlib.Path) -> int:
    bad = []
    checked = longest = 0

    # Tracked files only, so a scratch file in the worktree is never measured.
    listing = subprocess.run(["git", "ls-files"], cwd=repo, text=True,
                             capture_output=True)
    if listing.returncode != 0:
        print("  ! git ls-files failed")
        return 1

    for rel in listing.stdout.splitlines():
        if not rel or rel.startswith(SKIP):
            continue
        f = repo / rel
        if not f.is_file():
            continue
        # .tmpl is a real extension here — the template body is what is read —
        # so try the raw name first and the demangled one second.
        raw = pathlib.PurePosixPath(rel).name
        token = (BY_EXT.get(pathlib.PurePosixPath(raw).suffix)
                 or BY_NAME.get(target_name(raw))
                 or BY_EXT.get(pathlib.PurePosixPath(target_name(raw)).suffix))
        if not token:
            continue
        checked += 1

        # A sentinel blank line so a block running to EOF is still closed.
        lines = f.read_text(errors="replace").splitlines() + [""]
        run = start = 0
        waived = False
        for n, line in enumerate(lines, 1):
            text = line.strip()
            # A shebang is not a comment, and must not merge with the paragraph
            # under it. A bare token is the separator, so it ends the paragraph
            # below rather than extending it.
            if (text.startswith(token) and text != token
                    and not (n == 1 and text.startswith("#!"))):
                if run == 0:
                    start, waived = n, WAIVER in text
                run += 1
                continue
            if run and not waived:
                longest = max(longest, run)
                if run > MAX:
                    bad.append(f"{rel}:{start} comment block of {run} lines over the "
                               f"{MAX}-line budget — shorten it, move the durable part "
                               f"into docs/, or put '{WAIVER} <reason>' on its first line")
            run = 0

    for b in bad:
        print(f"  ! {b}")
    print(f"  ! {len(bad)} problem(s)" if bad
          else f"  . {checked} file(s) measured, longest block {longest} line(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")))
