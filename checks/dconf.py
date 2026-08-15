#!/usr/bin/env python3
"""Verify the GNOME dconf payloads against the schemas installed here.

A typo in a section path or key is silent: `dconf load` accepts anything, and
the setting simply never takes effect. This is the only check that needs the
machine it runs on to have the desktop installed, so on everything else it
reports what it could not check rather than passing.

Reads the schema XML rather than GSettings: `gi` is not importable from the
mise-managed python3, and PyGObject is a separate distro package.
"""

import pathlib
import sys
import xml.etree.ElementTree as ET

SCHEMA_DIR = pathlib.Path("/usr/share/glib-2.0/schemas")


def main(repo: pathlib.Path) -> int:
    payloads = sorted((repo / "home/.chezmoitemplates/desktop").glob("*.dconf"))
    if not payloads:
        print("  ! no dconf payloads found")
        return 1

    # The directory existing does NOT mean a desktop is installed — glib itself
    # ships schemas into it. The per-file check below decides.
    if not SCHEMA_DIR.is_dir():
        print("  . no glib schemas installed, skipped")
        return 0

    schemas, keys = {}, {}
    for x in SCHEMA_DIR.glob("*.gschema.xml"):
        try:
            root = ET.parse(x).getroot()
        except ET.ParseError:
            continue
        for s in root.iter("schema"):
            path = s.get("path")
            if not path:  # relocatable: no fixed path to check against
                continue
            p = path.strip("/")
            schemas[p] = s.get("id")
            keys[p] = {k.get("name") for k in s.iter("key")}

    # Path prefixes some installed schema sits under.
    installed_under = {p.rsplit("/", 1)[0] for p in schemas}

    bad = 0
    for f in payloads:
        section, checked, skipped = None, 0, 0
        for n, line in enumerate(f.read_text().splitlines(), 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("["):
                section = line[1:-1].strip("/")
                if section in schemas:
                    checked += 1
                elif section.rsplit("/", 1)[0] not in installed_under:
                    # Nothing from this component is installed at all, so there
                    # is nothing to check the section against. This cannot catch
                    # a typo in the parent prefix itself; one in the last
                    # component still fails, because its siblings are installed.
                    skipped += 1
                    section = None
                else:
                    print(f"  ! {f.name}:{n} no installed schema at /{section}/")
                    bad += 1
                    section = None
                continue
            key = line.split("=", 1)[0].strip()
            if section in keys and key not in keys[section]:
                print(f"  ! {f.name}:{n} {schemas[section]} has no key '{key}'")
                bad += 1
        print(f"  . {f.name}: {checked} section(s) checked"
              + (f", {skipped} not installed here" if skipped else ""))

    print(f"  ! {bad} problem(s)" if bad else "  . dconf payloads valid")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")))
