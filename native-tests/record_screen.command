#!/bin/bash
# native-tests/record_screen.command
# 在 Terminal（需已获屏幕录制权限）里录制 14s 屏幕到 /tmp/agentspur-native-demo.mov。
# 录完自动退出；由 tmux 侧的 drive_popover.sh 在 /tmp/agentspur-rec-started 出现后驱动 Popover。
exec > /tmp/agentspur-rec.log 2>&1
PERM=$(/usr/bin/xcrun swift -e 'import CoreGraphics; print(CGPreflightScreenCaptureAccess())' 2>/dev/null)
[ "$PERM" = "true" ] || { echo "PREFLIGHT_FALSE"; exit 3; }
rm -f /tmp/agentspur-rec-started /tmp/agentspur-native-demo.mov
osascript -e 'tell application "Terminal" to set miniaturized of front window to true' >/dev/null 2>&1
sleep 1
/usr/sbin/screencapture -x -v -V 14 /tmp/agentspur-native-demo.mov &
REC=$!
sleep 1
touch /tmp/agentspur-rec-started
wait $REC
echo "SCREENCAPTURE_EXIT:$?"
ls -lh /tmp/agentspur-native-demo.mov 2>&1
