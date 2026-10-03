#!/bin/bash
# 用法: win.sh normal | tall   —— normal=标准 1051x732@255,87（与 00–39 号图一致）；tall=加高 1051x870@255,25（露出侧栏底部）
case "$1" in
  tall)   osascript -e 'tell application "System Events" to tell process "Todo清单" to set position of window 1 to {255, 25}' -e 'tell application "System Events" to tell process "Todo清单" to set size of window 1 to {1051, 870}' >/dev/null 2>&1 ;;
  normal) osascript -e 'tell application "System Events" to tell process "Todo清单" to set size of window 1 to {1051, 732}' -e 'tell application "System Events" to tell process "Todo清单" to set position of window 1 to {255, 87}' >/dev/null 2>&1 ;;
  *) echo "用法: win.sh normal|tall"; exit 1 ;;
esac
sleep 0.7; bash "$(dirname "$0")/appwin.sh"
