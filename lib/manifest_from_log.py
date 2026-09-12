#!/usr/bin/env python3
"""Derive an undo list from an install log written before manifests existed.

The log is prose with the commands mixed in: every executed command appears as
a RUN line. That is enough to reconstruct most of what a run changed, with one
caveat the caller must respect -- the log cannot say whether a package was
already on the machine, only that dnf was asked for it. install.sh only ever
asks for packages it found missing, so the inference is sound for logs it
wrote, and unsound for anything else.

Reads a log path, writes manifest lines (kind<TAB>value) to stdout.
"""
import re
import shlex
import sys

# A package name that must never be handed to `dnf remove`, whatever the log
# says: removing any of these breaks the machine rather than the desktop.
CRITICAL = {
    "kernel", "kernel-core", "dnf", "dnf5", "rpm", "systemd", "glibc", "bash",
    "sudo", "NetworkManager", "selinux-policy", "grub2-common", "shim",
}


def is_package(word):
    if word.startswith("-"):
        return False
    if "://" in word or word.endswith(".rpm") or "/" in word:
        return False
    return bool(word) and word not in CRITICAL


def parse(argv, out):
    """Turn one command line into zero or more manifest entries."""
    if not argv:
        return
    if argv[0] == "sudo":
        argv = argv[1:]
        if not argv:
            return

    cmd = argv[0]
    rest = argv[1:]

    if cmd == "dnf" or cmd == "dnf5":
        if rest[:1] == ["install"]:
            for w in rest[1:]:
                if is_package(w):
                    out.append(("pkg", w))
        elif rest[:2] == ["copr", "enable"]:
            for w in rest[2:]:
                if not w.startswith("-"):
                    out.append(("copr", w))
                    break
        elif rest[:1] == ["config-manager"]:
            for w in rest:
                m = re.match(r"--from-repofile=(.*)", w)
                if m:
                    name = m.group(1).rstrip("/").split("/")[-1]
                    if name.endswith(".repo"):
                        out.append(("repofile", "/etc/yum.repos.d/" + name))
        return

    if cmd == "flatpak" and rest[:1] == ["install"]:
        args = [w for w in rest[1:] if not w.startswith("-")]
        if len(args) >= 2:               # ... flathub <app-id>
            out.append(("flatpak", args[-1]))
        return

    if cmd == "cp":
        args = [w for w in rest if not w.startswith("-")]
        if len(args) >= 2:
            dest = args[-1].rstrip("/")
            if dest.endswith("/."):
                dest = dest[:-2]
            out.append(("file", dest))
        return

    if cmd == "tee":
        for w in rest:
            if not w.startswith("-"):
                out.append(("file", w))
                break
        return

    if cmd == "ln":
        args = [w for w in rest if not w.startswith("-")]
        if len(args) >= 2:
            out.append(("symlink", args[-1]))
        return

    if cmd == "git" and "clone" in rest:
        args = [w for w in rest if not w.startswith("-")]
        if len(args) >= 3 and args[-1] != args[-2]:
            out.append(("file", args[-1]))
        return

    if cmd == "chsh":
        user = rest[-1] if rest and not rest[-1].startswith("-") else ""
        # The log does not carry the shell that was in place before.
        out.append(("shell", (user or "$USER") + "\t"))
        return

    if cmd == "systemctl":
        user = "--user" in rest
        args = [w for w in rest if not w.startswith("-")]
        if args[:1] == ["enable"]:
            for unit in args[1:]:
                out.append(("unit-user" if user else "unit-system", unit))
        elif args[:1] == ["set-default"]:
            out.append(("target", "multi-user.target"))
        return


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: manifest_from_log.py <install log>")
    out = []
    with open(sys.argv[1], errors="replace") as fh:
        for line in fh:
            m = re.match(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d RUN\s+(.*)$", line.rstrip("\n"))
            if not m:
                continue
            try:
                argv = shlex.split(m.group(1))
            except ValueError:
                continue
            parse(argv, out)

    seen = set()
    for kind, value in out:
        if (kind, value) in seen:
            continue
        seen.add((kind, value))
        print(f"{kind}\t{value}")


if __name__ == "__main__":
    main()
