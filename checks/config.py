#!/usr/bin/env python3
"""Assert this repo's invariants against the rendered target state.

Takes the directory checks/render.sh wrote. Three things are checked, and all
three are things a template can silently get wrong:

  - every rendered config still parses as the format its extension claims;
  - .chezmoiignore drops the right files on the right machine;
  - each script is gated to the machines that can run it.

Stdlib only: CI installs no Python packages, so YAML is out of scope and is
counted as skipped rather than quietly passed.
"""

import json
import pathlib
import sys
import tomllib

bad = []


def parsed(path: pathlib.Path) -> None:
    """Reparse a rendered file in the format its name promises."""
    try:
        if path.suffix == ".toml":
            tomllib.loads(path.read_text())
        elif path.suffix == ".json":
            json.loads(path.read_text())
    except (tomllib.TOMLDecodeError, json.JSONDecodeError) as e:
        bad.append(f"{path.parent.name}: {path.name} does not parse: {e}")


# A machine's target state, keyed by the directory render.sh named it.
def files(machine: pathlib.Path) -> set[str]:
    root = machine / "files"
    return {
        str(p.relative_to(root))
        for p in root.rglob("*")
        if p.is_file() or p.is_symlink()
    }


def scripts(machine: pathlib.Path) -> set[str]:
    return {p.name for p in (machine / "scripts").iterdir()}


# rel path -> the machines that must have it, and the ones that must not.
# Expressed as a predicate over the machine id so a new machine is covered by
# construction rather than by another table entry.
def is_windows(m: str) -> bool:
    return m.startswith("windows-")


def is_wsl(m: str) -> bool:
    return "-true-" in m


def is_linux(m: str) -> bool:
    return not is_windows(m) and not m.startswith("darwin-")


def is_work(m: str) -> bool:
    return m.endswith("-true")


RULES = [
    # (description, predicate, path, present?)
    ("the pwsh profile is Windows-only",
     is_windows, "Documents/PowerShell/Microsoft.PowerShell_profile.ps1", True),
    ("Windows Terminal settings are Windows-only", is_windows,
     "AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe"
     "/LocalState/settings.json", True),
    ("zsh is not installed on Windows",
     lambda m: not is_windows(m), ".zshrc", True),
    ("kitty is not installed on Windows",
     lambda m: not is_windows(m), ".config/kitty/kitty.conf", True),
    # The Windows host owns the agent under WSL, so a guest copy would be a
    # second, unread configuration.
    ("1Password's agent config is absent under WSL",
     lambda m: not is_wsl(m), ".config/1Password/ssh/agent.toml", True),
    ("the work git identity exists only on a work machine",
     is_work, ".config/git/config.work", True),
]

SCRIPT_RULES = [
    ("packages are installed per family", lambda m: is_windows(m),
     "run_onchange_before_10-packages-windows.ps1", True),
    ("the docker group is only joined on Linux", is_linux,
     "run_after_36-linux-services.sh", True),
    ("the WSL script is rendered only under WSL", is_wsl,
     "run_after_37-wsl.sh", True),
    ("Arch power management is Arch-only", lambda m: m.startswith("arch-"),
     "run_after_38-arch-services.sh", True),
    ("dconf is loaded on a Linux desktop, never under WSL",
     lambda m: is_linux(m) and not is_wsl(m),
     "run_onchange_after_40-desktop-dconf.sh", True),
    ("macOS defaults are macOS-only", lambda m: m.startswith("darwin-"),
     "run_onchange_after_40-macos-defaults.sh", True),
]


def main(root: pathlib.Path) -> int:
    machines = sorted(p for p in root.iterdir() if p.is_dir())
    if not machines:
        print("  ! nothing rendered")
        return 1

    n_parsed = 0
    for machine in machines:
        for p in (machine / "files").rglob("*"):
            if p.is_file() and not p.is_symlink() and p.suffix in (".toml", ".json"):
                parsed(p)
                n_parsed += 1

        mid, have, ran = machine.name, files(machine), scripts(machine)

        for what, applies, rel, _ in RULES:
            want = applies(mid)
            if want and rel not in have:
                bad.append(f"{mid}: {rel} is missing — {what}")
            elif not want and rel in have:
                bad.append(f"{mid}: {rel} should not be applied — {what}")

        for what, applies, name, _ in SCRIPT_RULES:
            want = applies(mid)
            if want and name not in ran:
                bad.append(f"{mid}: {name} did not render — {what}")
            elif not want and name in ran:
                bad.append(f"{mid}: {name} rendered — {what}")

        # A shell script on Windows or a .ps1 anywhere else is a gate that was
        # written on the file body instead of the family.
        wrong = [s for s in ran if s.endswith(".ps1") != is_windows(mid)]
        if wrong:
            bad.append(f"{mid}: wrong interpreter for {', '.join(sorted(wrong))}")

        # An empty target is almost always a template whose only content sat
        # inside a branch that this machine did not take.
        for p in (machine / "files").rglob("*"):
            if p.is_file() and not p.is_symlink() and p.stat().st_size == 0:
                bad.append(f"{mid}: {p.relative_to(machine / 'files')} rendered empty")

    for b in bad:
        print(f"  ! {b}")
    print(f"  ! {len(bad)} problem(s)" if bad else
          f"  . {len(machines)} machine(s), {n_parsed} config(s) valid "
          f"(YAML not checked: no stdlib parser)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(pathlib.Path(sys.argv[1])))
