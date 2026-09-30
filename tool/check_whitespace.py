"""Check tracked text files for trailing whitespace and mixed line endings."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def tracked_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        check=True,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
    )
    return [Path(item) for item in result.stdout.split("\0") if item]


def violations(path: Path) -> list[str]:
    try:
        data = path.read_bytes()
    except OSError as exc:
        return [f"{path}: cannot read: {exc}"]
    if b"\x00" in data:
        return []
    issues: list[str] = []
    if b"\r\n" in data and b"\n" in data.replace(b"\r\n", b""):
        issues.append(f"{path}: mixed CRLF/LF line endings")
    for number, line in enumerate(data.splitlines(), 1):
        if line.endswith((b" ", b"\t")):
            issues.append(f"{path}:{number}: trailing whitespace")
    return issues


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path)
    args = parser.parse_args()
    paths = args.paths or tracked_files()
    problems = [problem for path in paths for problem in violations(path)]
    if problems:
        print("\n".join(problems))
        return 1
    print(f"Checked {len(paths)} text candidates: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
