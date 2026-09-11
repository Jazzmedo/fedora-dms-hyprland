#!/usr/bin/env python3
"""Merge a KDE .colors scheme into kdeglobals.

Installing a scheme into ~/.local/share/color-schemes only makes it *offerable*
in the system settings dialogue. KDE applications read the palette they
actually paint with from the [Colors:*] sections of kdeglobals, and Plasma is
what normally copies one into the other. Under Hyprland there is no Plasma, so
Dolphin falls back to Breeze light no matter what ColorScheme= says.

Usage: kde_palette.py <scheme.colors> <kdeglobals>
"""
import os
import sys

scheme_path, target_path = sys.argv[1], sys.argv[2]

# Sections that describe colour rather than behaviour. Everything else in the
# scheme file (window decoration metadata, the scheme's own [General] name) is
# either irrelevant or would clobber the user's settings.
WANTED = ("Colors:", "ColorEffects:", "WM")


def read_sections(path):
    """[(name, [lines]), ...]; lines before the first header get name ''."""
    out, name, buf = [], "", []
    try:
        fh = open(path, encoding="utf-8")
    except OSError:
        return out
    with fh:
        for line in fh:
            line = line.rstrip("\n")
            if line.startswith("[") and line.endswith("]"):
                out.append((name, buf))
                name, buf = line[1:-1], []
            else:
                buf.append(line)
    out.append((name, buf))
    return out


def wanted(name):
    return any(name == w or name.startswith(w) for w in WANTED)


scheme = read_sections(scheme_path)
if not scheme:
    sys.exit(f"cannot read {scheme_path}")

incoming = [(n, b) for n, b in scheme if wanted(n)]
if not incoming:
    sys.exit(f"{scheme_path} carries no colour sections")

names = {n for n, _ in incoming}
kept = [(n, b) for n, b in read_sections(target_path) if n not in names]

# The scheme's own name, so the settings dialogue agrees with what is painted.
label = next((l.split("=", 1)[1] for n, b in scheme if n == "General"
              for l in b if l.startswith("ColorScheme=")), None)
if label:
    for i, (n, b) in enumerate(kept):
        if n != "General":
            continue
        b = [l for l in b if not l.startswith("ColorScheme=")]
        while b and not b[-1].strip():
            b.pop()
        b.append(f"ColorScheme={label}")
        kept[i] = (n, b)
        break
    else:
        kept.append(("General", [f"ColorScheme={label}"]))


def strip_trailing_blanks(lines):
    while lines and not lines[-1].strip():
        lines.pop()
    return lines


os.makedirs(os.path.dirname(target_path) or ".", exist_ok=True)
with open(target_path, "w", encoding="utf-8") as fh:
    for name, body in kept + incoming:
        if name:
            fh.write(f"[{name}]\n")
        for line in strip_trailing_blanks(list(body)):
            fh.write(line + "\n")
        fh.write("\n")

print(f"kdeglobals: {len(incoming)} colour sections from "
      f"{os.path.basename(scheme_path)}")
