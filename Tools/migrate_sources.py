#!/usr/bin/env python3
"""Stage legacy NoqeriOS sources for the current .noqeri compiler.

The original .nqr files are left untouched so this migration is reversible.
Only imports ending in .nqr are rewritten; string literals elsewhere remain
unchanged. Refuse path traversal and symlink escapes when staging.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import shutil
import sys

IMPORT = re.compile(r'(\bimport\s+"[^"\n]*?)\.nqr(")')


def migrate(root: Path, destination: Path) -> int:
    root = root.resolve(strict=True)
    destination = destination.resolve()
    if destination == root or root in destination.parents and destination.name == ".deps":
        raise ValueError("invalid staging destination")
    files = []
    for source in sorted(root.rglob("*.nqr")):
        relative = source.relative_to(root)
        if any(part in {".git", ".deps", "build"} for part in relative.parts):
            continue
        if not source.is_file() or source.is_symlink():
            raise ValueError(f"refusing linked or missing source: {relative}")
        files.append((source, relative))
    if not files:
        raise ValueError("No legacy .nqr source files found; verify the source layout")
    for source, relative in files:
        target = destination / relative.with_suffix(".noqeri")
        target.parent.mkdir(parents=True, exist_ok=True)
        data = source.read_text(encoding="utf-8")
        data = IMPORT.sub(r"\1.noqeri\2", data)
        target.write_text(data, encoding="utf-8")
    entry = destination / "Kernel/main.noqeri"
    if not entry.is_file():
        raise ValueError("Kernel/main.nqr is missing")
    print(f"Staged {len(files)} Noqeri modules at {destination}")
    return len(files)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    try:
        migrate(args.root, args.destination)
    except (OSError, ValueError, UnicodeError) as exc:
        print(f"NoqeriOS source migration error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
