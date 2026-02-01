#!/bin/bash
# .claude/hooks/notify-stop.sh

# 터미널 탭/창 식별 (iTerm2, Terminal.app 등)
TAB_ID="${ITERM_SESSION_ID:-${TERM_SESSION_ID:-$$}}"

osascript -e "display notification \"Waiting for input\" with title \"Claude Code\" subtitle \"Session: $TAB_ID\""