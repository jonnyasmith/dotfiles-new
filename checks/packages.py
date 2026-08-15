#!/usr/bin/env python3
"""Assert the two rules .chezmoidata/packages.toml is written to.

  registry rule — a package mise's registry can install belongs in [tools],
  where one version is pinned for every OS. An entry here that the registry
  matches exactly is drift waiting to happen, so it must carry a reason.

  Linux parity — a package declared for two of the three Linux families and not
  the third is almost always an oversight. When it is not, every existing entry
  says so.

Read as text rather than through tomllib, because both waivers live in trailing
comments and tomllib discards them.
"""

import os
import pathlib
import re
import shutil
import subprocess
import sys

# The array under each [packages.<family>] table, mapped to what installs it.
MANAGERS = {
    ("darwin", "formulae"): "brew",
    ("darwin", "linkedFormulae"): "brew",
    ("darwin", "casks"): "brew-cask",
    ("debian", "core"): "apt",
    ("debian", "desktop"): "apt",
    ("fedora", "core"): "dnf",
    ("fedora", "desktop"): "dnf",
    ("arch", "core"): "pacman",
    ("arch", "hardware"): "pacman",
    ("arch", "aur"): "aur",
    ("windows", "winget"): "winget",
}

# Where the registry rule bites: managers whose packages mise could also supply.
# brew-cask, aur and winget ship GUI apps and vendor bundles the registry has no
# equivalent for.
ONPATH = ("apt", "dnf", "pacman", "brew")
DISTRO = ("apt", "dnf", "pacman")


def declarations(path: pathlib.Path):
    """(manager, package, waivers) for every entry, in file order."""
    family = key = None
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if m := re.match(r"\[packages\.(\w+)\]", stripped):
            family, key = m.group(1), None
            continue
        if m := re.match(r"(\w+)\s*=\s*\[", stripped):
            key = m.group(1)
            continue
        if stripped.startswith("]"):
            key = None
            continue
        if not (m := re.match(r'"(@?[^"]+)"\s*,', stripped)):
            continue
        mgr = MANAGERS.get((family, key))
        if mgr is None:
            yield None, f"{family}.{key}", set()
            continue
        comment = stripped.split("#", 1)[1] if "#" in stripped else ""
        waivers = {w for w in ("registry-skip", "parity-skip") if w + ":" in comment}
        yield mgr, m.group(1), waivers


def main(repo: pathlib.Path) -> int:
    # The registry half shells out to `mise search`. Without it the check would
    # find nothing and report success, so it stops instead.
    if shutil.which("mise") is None:
        print("  ! mise is required — the registry rule is a registry lookup")
        return 1

    bad = []
    entries = []
    for mgr, pkg, waivers in declarations(repo / "home/.chezmoidata/packages.toml"):
        if mgr is None:
            bad.append(f"no manager is defined for [packages.{pkg}] — add it to MANAGERS")
            continue
        entries.append((mgr, pkg, waivers))

    # --- registry rule ---------------------------------------------------
    for mgr, pkg, waivers in entries:
        if mgr not in ONPATH or "registry-skip" in waivers:
            continue
        hit = subprocess.run(
            ["mise", "search", "-m", "equal", "--no-header", pkg],
            capture_output=True, text=True, env=os.environ,
        )
        out = hit.stdout.strip()
        # `mise search` exits non-zero when nothing matches, which is the common
        # case. Anything else — a failed registry fetch, a mise too old for
        # these flags — must not read as "no match", or this half passes
        # vacuously.
        if hit.returncode != 0 and not re.search(r"not found in registry", hit.stderr):
            first = hit.stderr.strip().splitlines()
            bad.append(f"{mgr}:{pkg}: registry lookup failed: "
                       f"{first[0] if first else hit.returncode}")
        elif out:
            bad.append(f"{mgr}:{pkg} has an exact registry match ({out.split()[0]}) — "
                       f"move it to [tools] in dot_config/mise/config.toml.tmpl, "
                       f"or add '# registry-skip: <reason>'")

    # --- Linux parity ----------------------------------------------------
    by_pkg: dict[str, dict[str, set]] = {}
    for mgr, pkg, waivers in entries:
        if mgr in DISTRO:
            by_pkg.setdefault(pkg, {})[mgr] = waivers
    for pkg, mgrs in sorted(by_pkg.items()):
        if len(mgrs) != 2 or all("parity-skip" in w for w in mgrs.values()):
            continue
        missing = ", ".join(sorted(set(DISTRO) - set(mgrs)))
        bad.append(f"{pkg} is declared for {', '.join(sorted(mgrs))} but not {missing} — "
                   f"declare it there, or add '# parity-skip: <reason>' to every "
                   f"existing entry")

    for b in bad:
        print(f"  ! {b}")
    print(f"  ! {len(bad)} problem(s)" if bad
          else f"  . {len(entries)} package declaration(s) valid")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")))
