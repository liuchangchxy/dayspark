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
# DaySpark pre-commit gate: dart analyze . must be green (zero exit).
# flutter test is intentionally NOT run here (too slow); tests are gated by workflow.

echo "============================================================"
echo " [pre-commit] Running: dart analyze ."
echo "============================================================"

dart analyze .
RESULT=$?

if [ $RESULT -ne 0 ]; then
  echo ""
  echo "[BLOCKED] dart analyze reported issues; commit rejected."
  echo "Fix the analyzer output above, then commit again."
  echo "============================================================"
  exit 1
fi

echo ""
echo "[PASSED] dart analyze clean. Proceeding with commit."
echo "============================================================"
exit 0
EOF

chmod 755 "$HOOK_PATH"
echo "[SUCCESS] installed $HOOK_PATH (executable)"
echo "[INFO] gate: dart analyze . ; tests remain a workflow gate (flutter test)."
