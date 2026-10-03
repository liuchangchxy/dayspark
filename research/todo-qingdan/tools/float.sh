#!/bin/bash
# 用法: float.sh <输出png路径> [捕获余量px]  —— 截「小窗口」（番茄钟悬浮窗等），不是主窗口
OUT="$1"; PAD="${2:-120}"
R=$(osascript <<'EOF' 2>/dev/null
tell application "System Events" to tell process "Todo清单"
  set best to missing value
  set bestArea to 999999999
  repeat with w in windows
    try
      set s to size of w
      set a to (item 1 of s) * (item 2 of s)
      if a < bestArea then
        set bestArea to a
        set best to w
      end if
    end try
  end repeat
  if best is missing value then return "NOWIN"
  set p to position of best
  set s to size of best
  return ((item 1 of p) as string) & "," & ((item 2 of p) as string) & "," & ((item 1 of s) as string) & "," & ((item 2 of s) as string)
end tell
EOF
)
[ "$R" = "NOWIN" ] && { echo "FAIL: 没有小窗口"; exit 1; }
X=$(echo "$R" | cut -d, -f1); Y=$(echo "$R" | cut -d, -f2); W=$(echo "$R" | cut -d, -f3); H=$(echo "$R" | cut -d, -f4)
RX=$((X-PAD)); RY=$((Y-PAD)); RW=$((W+PAD*2)); RH=$((H+PAD*2))
[ $RX -lt 0 ] && RX=0; [ $RY -lt 0 ] && RY=0
screencapture -x -R"$RX,$RY,$RW,$RH" "$OUT" && echo "OK $OUT （小窗口 $R，含余量）"
