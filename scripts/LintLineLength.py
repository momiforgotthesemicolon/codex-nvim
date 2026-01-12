#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
MAX_LEN = 80
PATTERNS = [
    "lua/**/*.lua",
    "plugin/**/*.lua",
    "README.md",
]


def iter_files(root: Path) -> list[Path]:
    paths: list[Path] = []
    for pattern in PATTERNS:
        paths.extend(root.glob(pattern))
    return sorted({path for path in paths if path.is_file()})


def check_file(path: Path) -> list[tuple[int, int, str]]:
    violations: list[tuple[int, int, str]] = []
    lines = path.read_text(encoding="utf-8").splitlines()
    for idx, line in enumerate(lines, 1):
        length = len(line)
        if length > MAX_LEN:
            violations.append((idx, length, line))
    return violations


def main() -> int:
    files = iter_files(ROOT)
    failures: list[str] = []
    for path in files:
        for line_no, length, line in check_file(path):
            rel = path.relative_to(ROOT)
            snippet = line[:MAX_LEN].rstrip()
            failures.append(
                f"{rel}:{line_no} length {length} > {MAX_LEN}: {snippet}"
            )
    if failures:
        print("\n".join(failures))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
