#!/bin/bash
# native-tests/drive_popover.sh
# tmux 侧（AX 可用）驱动：等录制开始 → 打开 Popover 5s → 关闭 Popover。
set -u
rm -f /tmp/agentspur-rec-started
for i in $(seq 1 60); do [ -f /tmp/agentspur-rec-started ] && break; sleep 0.5; done
[ -f /tmp/agentspur-rec-started ] || { echo NO_RECORDER; exit 1; }
sleep 1
osascript -e 'tell application "System Events" to tell process "AgentSpur" to perform action "AXPress" of menu bar item 1 of menu bar 2'
sleep 5
osascript -e 'tell application "System Events" to tell process "AgentSpur" to perform action "AXPress" of menu bar item 1 of menu bar 2'
echo DRIVE_DONE
