#!/bin/bash
# native-tests/run_menu_bar_test.sh
# AgentSpur 原生菜单栏 App 的 AX 自动化测试（6 项断言）。
# 只用 AXPress / AX 读取；不修改产品代码、不点坐标、不碰 /Applications。
# 输出：native-tests/result.txt（完整明细）+ 控制台 PASS/FAIL。
# 退出码：0 = 6/6 全通过；1 = 有断言失败或 AppleScript 出错。

set -u
cd "$(dirname "$0")" || exit 2

OUT="result.txt"
RAW="$(mktemp /tmp/agentspur-ax-raw.XXXXXX)"

echo "== AgentSpur native AX test: $(date '+%Y-%m-%d %H:%M:%S') =="
/usr/bin/osascript ax_test.applescript >"$RAW" 2>&1
rc=$?

{
  echo "== AgentSpur native AX test =="
  echo "run_at: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "script: native-tests/ax_test.applescript"
  echo ""
  cat "$RAW"
  echo "EXIT_CODE: $rc"
} >"$OUT"

cat "$RAW"
echo ""
echo "---- 断言汇总 ----"
grep -E '^\[(PASS|FAIL)\]' "$RAW" || echo "(无可解析的断言行)"
echo "result_file: native-tests/result.txt"

if [ "$rc" -eq 0 ] && grep -q '^RESULT: PASS 6/6' "$RAW"; then
  echo "OVERALL: PASS"
  rm -f "$RAW"
  exit 0
fi

echo "OVERALL: FAIL"
rm -f "$RAW"
exit 1
