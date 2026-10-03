#!/bin/bash
# 用法: drag.sh <x1> <y1> <x2> <y2> <输出png> [松开后延时]
X1="$1"; Y1="$2"; X2="$3"; Y2="$4"; OUT="$5"; D="${6:-1.0}"
osascript -e 'tell application "Todo清单" to activate' >/dev/null 2>&1
osascript -e 'delay 0.35' >/dev/null 2>&1
/opt/homebrew/bin/cliclick dd:$X1,$Y1
sleep 0.25
# 分步移动：WebView 需要中间的 mousemove 才会进入拖拽态
for i in 1 2 3 4 5 6 7 8; do
  MX=$(( X1 + (X2-X1)*i/8 )); MY=$(( Y1 + (Y2-Y1)*i/8 ))
  /opt/homebrew/bin/cliclick dm:$MX,$MY
  sleep 0.12
done
sleep 0.3
if [ "$OUT" != "none" ]; then
  R=$(bash "$(dirname "$0")/appwin.sh")
  screencapture -x -R"$R" "$OUT"
fi
/opt/homebrew/bin/cliclick du:$X2,$Y2
sleep "$D"
if [ "$OUT" != "none" ]; then echo "OK $OUT（拖拽中截图）"; else echo "OK 拖拽完成"; fi
