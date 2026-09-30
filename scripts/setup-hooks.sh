#!/usr/bin/env bash
# 安装/重装本仓库的 git hooks（.git 不版本化 hooks，clone 后需重跑本脚本）。
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -d .git ]; then
  echo "[ERROR] .git 不存在，当前目录不是 git 仓库。" >&2
  exit 1
fi

mkdir -p .git/hooks

HOOK_PATH=".git/hooks/pre-commit"
cat > "$HOOK_PATH" <<'EOF'
#!/bin/sh
# DaySpark pre-commit gate.
#   dart analyze  —— 必须零 issue（快，每次提交都跑）
#   防测试篡改     —— 拦住"放宽断言/删用例来造绿"（快，扫 git diff）
#   硬编码绝对路径 —— 拦住写死本机路径（快，扫 git 跟踪的文件）
# flutter test 故意不在此处跑（太慢）；全量测试由 CI 与发布流程卡口。

echo "============================================================"
echo " [pre-commit] analyze + 防篡改 + 硬编码路径"
echo "============================================================"

dart analyze .
if [ $? -ne 0 ]; then
  echo ""
  echo "[BLOCKED] dart analyze 报出问题，提交被拒。修好上面的输出再提交。"
  echo "============================================================"
  exit 1
fi

if [ -f "tool/guard_test_tampering.py" ]; then
  python3 tool/guard_test_tampering.py || exit 1
fi

if [ -f "tool/scan_hardcoded_paths.py" ]; then
  python3 tool/scan_hardcoded_paths.py || exit 1
fi

echo ""
echo "[PASSED] 全部门禁通过，继续提交。"
echo "============================================================"
exit 0
EOF

chmod 755 "$HOOK_PATH"
echo "[SUCCESS] installed $HOOK_PATH (executable)"
echo "[INFO] gates: dart analyze . + 防测试篡改 + 硬编码路径扫描"
echo "[INFO] flutter test 仍是 CI/发布门禁（此处不跑，太慢）。"
