#!/bin/zsh
# usage: shot.sh <file.html> <out.png> <width> <height> [scale]
page="$1"; out="$2"; w="$3"; h="$4"; scale="${5:-1}"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
  --window-size="${w},${h}" --force-device-scale-factor="$scale" \
  --screenshot="$out" --virtual-time-budget=6000 \
  --user-data-dir="/tmp/ds-chrome-$$" "file://$page" >/dev/null 2>&1
rm -rf "/tmp/ds-chrome-$$"
echo "$out"
