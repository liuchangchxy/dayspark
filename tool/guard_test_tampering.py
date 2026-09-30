#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
guard_test_tampering.py - 防测试篡改物理检验脚本
用于检查当前 Git 变更中是否存在对既有测试用例断言（assert / expect / toBe）的随意修改或删除。
"""

import sys
import subprocess
from pathlib import Path

# 针对 Windows 终端 GBK 编码进行加固
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# 易受篡改的测试断言特征词
ASSERTION_KEYWORDS = (
    "assert ",
    "assert_equal",
    "expect(",
    ".toBe(",
    ".toEqual(",
    ".toStrictEqual(",
    ".toMatch(",
    ".assertTrue(",
    ".assertFalse(",
    ".assertEqual(",
    ".assertRaises(",
)

def run_git_diff() -> str:
    """获取暂存区与工作区的完整 diff"""
    try:
        res = subprocess.run(
            ["git", "diff", "HEAD", "--unified=0"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace"
        )
        if res.returncode != 0:
            # 如果没有 HEAD，回退到无 HEAD diff
            res = subprocess.run(
                ["git", "diff", "--unified=0"],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace"
            )
        return res.stdout
    except Exception as e:
        print(f"⚠️ [防篡改检查] 读取 Git Diff 失败: {e}", file=sys.stderr)
        return ""

def check_tampering(diff_text: str) -> list[str]:
    """分析 diff 中是否有测试文件被删除了断言行"""
    violations = []
    current_file = ""
    is_test_file = False

    for line in diff_text.splitlines():
        if line.startswith("diff --git "):
            parts = line.split()
            current_file = parts[-1].lstrip("b/")
            # 识别测试文件
            is_test_file = any(
                p in current_file.lower()
                for p in ["test_", "_test.", ".spec.", ".test.", "tests/"]
            )
            continue

        if not is_test_file:
            continue

        # 检查被删除的行（以 - 开头，但不包含文件头 ---）
        if line.startswith("-") and not line.startswith("---"):
            removed_content = line[1:].strip()
            # 如果被删除的行包含核心断言语句
            if any(removed_content.startswith(kw) or f" {kw}" in removed_content for kw in ASSERTION_KEYWORDS):
                violations.append(f"文件 [{current_file}] 中检测到核心断言被修改或删除: '{removed_content}'")

    return violations

def main():
    diff_text = run_git_diff()
    if not diff_text.strip():
        # 无变更
        sys.exit(0)

    violations = check_tampering(diff_text)
    if violations:
        print("\n❌ [防测试篡改警报 (Anti-Test Tampering Gate)]", file=sys.stderr)
        print("检测到既有测试文件的断言预期被修改或删除！", file=sys.stderr)
        print("严格禁止通过篡改/弱化旧测试断言来伪造全绿，请正面修复业务逻辑。\n", file=sys.stderr)
        for v in violations:
            print(f"  🔴 {v}", file=sys.stderr)
        print("\n如确系合法的需求变更，请在提交说明中显式注明并在 DECISIONS.md 中记录。", file=sys.stderr)
        sys.exit(1)

    sys.exit(0)

if __name__ == "__main__":
    main()
