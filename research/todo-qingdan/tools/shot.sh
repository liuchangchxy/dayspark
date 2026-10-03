#!/bin/bash
# 用法: shot.sh <输出png路径> [延时秒]   —— 只激活+截图，不点击
OUT="$1"; D="${2:-0.6}"
osascript -e 'tell application "Todo清单" to activate' >/dev/null 2>&1
osascript -e "delay $D" >/dev/null 2>&1
R=$(bash "$(dirname "$0")/appwin.sh")
if [ "$R" = "NOWIN" ] || [ -z "$R" ]; then
  osascript -e 'tell application "System Events" to tell process "Todo清单" to set frontmost to true' >/dev/null 2>&1
  sleep 0.8
  R=$(bash "$(dirname "$0")/appwin.sh")
fi
[ "$R" = "NOWIN" ] && { echo "FAIL: 主窗口不存在（试试 open -a \"Todo清单\"）"; exit 1; }
screencapture -x -R"$R" "$OUT" && echo "OK $OUT  ($R)"
