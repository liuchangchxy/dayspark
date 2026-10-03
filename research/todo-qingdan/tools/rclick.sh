#!/bin/bash
# 用法: rclick.sh <x> <y> <输出png路径> [延时秒]   —— 右键
X="$1"; Y="$2"; OUT="$3"; D="${4:-0.9}"
osascript -e 'tell application "Todo清单" to activate' >/dev/null 2>&1
osascript -e 'delay 0.35' >/dev/null 2>&1
/opt/homebrew/bin/cliclick rc:$X,$Y
osascript -e "delay $D" >/dev/null 2>&1
R=$(bash "$(dirname "$0")/appwin.sh")
[ "$R" = "NOWIN" ] && { echo "FAIL: 主窗口不存在"; exit 1; }
screencapture -x -R"$R" "$OUT" && echo "OK $OUT  ($R)"
