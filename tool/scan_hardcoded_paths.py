#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scan_hardcoded_paths.py - 源码硬编码绝对路径扫描门禁
扫描项目源码中是否存在硬编码的系统级绝对路径（如 C:\\Users\\, /home/user/ 等）。
必须使用相对基准路径（如 Path(__file__).resolve().parent）或环境变量进行动态定位。
"""

import re
import subprocess
import sys
from pathlib import Path

# 针对 Windows 终端 GBK 编码进行加固
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# 排除目录
IGNORED_DIRS = {
    ".git", ".venv", "venv", "node_modules", "__pycache__",
    ".idea", ".vscode", "dist", "build", "coverage", ".pytest_cache"
}

ROOT = Path(__file__).resolve().parent.parent

# 忽略的文件后缀 (Markdown 文档包含反面示例说明，门禁聚焦代码执行源文件与配置文件)
IGNORED_EXTENSIONS = {
    ".pyc", ".png", ".jpg", ".jpeg", ".ico", ".svg", ".lock", ".log", ".md",
    ".jar", ".so", ".dylib", ".a", ".bin",
}

# 规则说明文档里举反例的地方，以及本脚本自身
SKIP_NAMES = {
    "scan_hardcoded_paths.py", "FAQ.md", "AGENTS.md", "README.md",
    "I18N_AND_THEME_ARCHITECTURE.md", "LOCALIZATION.md", "CONSTRAINTS.md",
}

# 违规硬编码绝对路径模式
FORBIDDEN_PATTERNS = [
    (re.compile(r'[a-zA-Z]:\\(?:Users|Documents|Desktop|Projects|code)\\', re.IGNORECASE), "Windows 本地用户绝对路径"),
    (re.compile(r'[a-zA-Z]:/(?:Users|Documents|Desktop|Projects|code)/', re.IGNORECASE), "Windows 正斜杠用户绝对路径"),
    (re.compile(r'/(?:Users|home)/[a-zA-Z0-9_\-]+/', re.IGNORECASE), "Unix/macOS 用户家目录绝对路径"),
]

def scan_file(file_path: Path) -> list[str]:
    violations = []
    try:
        content = file_path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return violations

    for line_num, line in enumerate(content.splitlines(), start=1):
        for pattern, desc in FORBIDDEN_PATTERNS:
            if pattern.search(line):
                violations.append(f"{file_path}:{line_num} -> [{desc}] {line.strip()[:100]}")
    return violations

def tracked_files() -> list[Path]:
    """Only Git-tracked files are scanned.

    Walking the filesystem instead would drag in vendored third-party sources
    (ios/Pods, node_modules, .dart_tool) whose fixture paths like
    "/home/fred/data.db" are not our code and cannot be fixed. Tracked files
    are exactly the files this project is responsible for.
    """
    out = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=str(ROOT), capture_output=True, encoding="utf-8", errors="replace", check=True,
    ).stdout
    return [ROOT / name for name in out.split("\0") if name]


def main():
    violations = []
    skipped = 0
    for path in tracked_files():
        if path.suffix.lower() in IGNORED_EXTENSIONS:
            continue
        if path.name in SKIP_NAMES:
            continue
        if not path.is_file():
            continue
        try:
            if b"\x00" in path.read_bytes()[:4096]:
                skipped += 1
                continue
        except OSError:
            continue
        violations.extend(scan_file(path))

    if violations:
        print("\n\u274c [\u786c\u7f16\u7801\u8def\u5f84\u95e8\u7981\u62e6\u622a (Hardcoded Path Gate)]", file=sys.stderr)
        print("\u68c0\u6d4b\u5230\u4ee3\u7801\u4e2d\u5b58\u5728\u786c\u7f16\u7801\u7269\u7406\u7edd\u5bf9\u8def\u5f84\uff01\u8fd9\u4f1a\u5bfc\u81f4\u4ee3\u7801\u5728\u4ed6\u4eba\u673a\u5668\u6216 CI \u73af\u5883\u4e2d\u76f4\u63a5\u5d29\u6e83\u3002", file=sys.stderr)
        print("\u5fc5\u987b\u4f7f\u7528\u76f8\u5bf9\u57fa\u51c6\u5b9a\u4f4d\u6216\u73af\u5883\u53d8\u91cf\u3002\n", file=sys.stderr)
        for v in violations:
            print(f"  \U0001f534 {v}", file=sys.stderr)
        sys.exit(1)

    print("\u2705 [\u786c\u7f16\u7801\u8def\u5f84\u68c0\u67e5\u901a\u8fc7] \u672a\u53d1\u73b0\u5199\u6b7b\u7269\u7406\u7edd\u5bf9\u8def\u5f84\u3002")
    sys.exit(0)


if __name__ == "__main__":
    main()
