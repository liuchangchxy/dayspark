#!/bin/bash
# 打印主窗口 "x,y,w,h"（屏幕坐标点）。
# 关键：番茄钟有独立悬浮窗，标题也叫「Todo清单」。所以取**面积最大的同名窗口**，不能取最后一个。
osascript <<'EOF' 2>/dev/null
tell application "System Events" to tell process "Todo清单"
  set best to missing value
  set bestArea to -1
  repeat with w in windows
    try
      if (name of w) is "Todo清单" then
        set s to size of w
        set a to (item 1 of s) * (item 2 of s)
        if a > bestArea then
          set bestArea to a
          set best to w
        end if
      end if
    end try
  end repeat
  if best is missing value then return "NOWIN"
  set p to position of best
  set s to size of best
  return ((item 1 of p) as string) & "," & ((item 2 of p) as string) & "," & ((item 1 of s) as string) & "," & ((item 2 of s) as string)
end tell
EOF
