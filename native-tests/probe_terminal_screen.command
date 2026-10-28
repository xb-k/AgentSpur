#!/bin/bash
# native-tests/probe_terminal_screen.command
# 在 Terminal 里探测「屏幕录制」权限（CGPreflightScreenCaptureAccess）。
# 只读探测，不触发录屏、不弹权限框。
exec > /tmp/agentspur-term-perm.log 2>&1
PERM=$(/usr/bin/xcrun swift -e 'import CoreGraphics; print(CGPreflightScreenCaptureAccess())' 2>/dev/null)
echo "TERM_PREFLIGHT:$PERM"
echo "TERM_TIME:$(date '+%Y-%m-%d %H:%M:%S')"
echo "TERM_USER:$(whoami)"
echo "TERM_TTY:$(tty)"
echo "TERM_BUNDLE:$(ps -o comm= -p $PPID)"
