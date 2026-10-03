#!/bin/bash
# 用法: keys.sh esc | enter | tab | cmd+n | type:<文本> | kp:<键码>
osascript -e 'tell application "Todo清单" to activate' >/dev/null 2>&1
osascript -e 'delay 0.3' >/dev/null 2>&1
case "$1" in
  esc) /opt/homebrew/bin/cliclick kp:esc ;;
  enter) /opt/homebrew/bin/cliclick kp:return ;;
  tab) /opt/homebrew/bin/cliclick kp:tab ;;
  kp:*) /opt/homebrew/bin/cliclick kp:${1#kp:} ;;
  type:*) osascript -e "tell application \"System Events\" to keystroke \"${1#type:}\"" ;;
  *) osascript -e "tell application \"System Events\" to keystroke \"$1\" using command down" ;;
esac
echo "sent: $1"
