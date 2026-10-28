-- native-tests/ax_test.applescript
-- AgentSpur 原生 AX 自动化测试（6 项断言）
-- 约定：只用 AXPress / AX 读取，不做坐标点击，不修改产品代码。
-- 输出由 run_menu_bar_test.sh 收集到 native-tests/result.txt。

on run
	set appName to "AgentSpur"
	set outLines to {}
	set passCount to 0
	set failCount to 0

	set end of outLines to "=== AgentSpur native AX test ==="
	set end of outLines to "time: " & my runShell("date '+%Y-%m-%d %H:%M:%S'")

	-- ---------- A1 进程存在 ----------
	set procExists to false
	tell application "System Events"
		if exists (application process appName) then set procExists to true
	end tell
	if procExists then
		set passCount to passCount + 1
		set end of outLines to "[PASS] A1 进程存在: " & appName
	else
		set failCount to failCount + 1
		set end of outLines to "[FAIL] A1 进程存在: 未找到 " & appName & " 进程"
		set end of outLines to ""
		set end of outLines to "RESULT: FAIL 0/6 (进程不存在，后续断言无法执行)"
		return my joinText(outLines)
	end if

	-- ---------- A2 状态项存在、标题含 ¥、状态词合法 ----------
	set itemTitle to ""
	set titleErr to ""
	try
		tell application "System Events" to tell process appName
			set itemTitle to (title of menu bar item 1 of menu bar 2) as text
		end tell
	on error errMsg
		set titleErr to errMsg
	end try
	set titleTrim to my trimText(itemTitle)
	set stateWord to ""
	if titleTrim contains "·" then
		set stateWord to my trimText(item 1 of my splitText(titleTrim, "·"))
	else
		set stateWord to titleTrim
	end if
	set allowedStates to {"思考", "工作", "待确认", "完成", "空闲"}
	set stateOK to my listContains(allowedStates, stateWord)
	set a2ok to (titleTrim is not "") and (titleTrim contains "¥") and stateOK
	if a2ok then
		set passCount to passCount + 1
		set end of outLines to "[PASS] A2 状态项标题合法: " & titleTrim
		set end of outLines to "      状态词: " & stateWord
	else
		set failCount to failCount + 1
		set end of outLines to "[FAIL] A2 状态项标题非法: " & titleTrim
		set end of outLines to "      状态词: " & stateWord & " (允许: 思考/工作/待确认/完成/空闲)"
		if titleErr is not "" then set end of outLines to "      读取错误: " & titleErr
	end if

	-- ---------- A3 AXPress 打开 Popover ----------
	set pressErr to ""
	try
		tell application "System Events" to tell process appName
			perform action "AXPress" of menu bar item 1 of menu bar 2
		end tell
	on error errMsg
		set pressErr to errMsg
	end try
	delay 1.0

	set popCount to 0
	set popRole to ""
	set popDesc to ""
	set focusText to ""
	tell application "System Events" to tell process appName
		try
			set popCount to (count of UI elements of menu bar item 1 of menu bar 2)
			if popCount > 0 then
				set popRole to (role of UI element 1 of menu bar item 1 of menu bar 2) as text
				set popDesc to (description of UI element 1 of menu bar item 1 of menu bar 2) as text
			end if
		end try
		try
			set fe to value of attribute "AXFocusedUIElement"
			set focusText to (role of fe as text) & " / " & (description of fe as text)
		end try
	end tell

	set a3ok to (popCount > 0) and (popRole is "AXPopover") and (focusText contains "AXPopover")
	if a3ok then
		set passCount to passCount + 1
		set end of outLines to "[PASS] A3 AXPress 打开 Popover: role=" & popRole & " count=" & popCount
	else
		set failCount to failCount + 1
		set end of outLines to "[FAIL] A3 AXPress 打开 Popover: count=" & popCount & " role=" & popRole
		if pressErr is not "" then set end of outLines to "      AXPress 错误: " & pressErr
	end if
	set end of outLines to "      Popover description: " & popDesc
	set end of outLines to "      AXFocusedUIElement: " & focusText

	-- ---------- A4 读取 Popover 内全部 AXStaticText ----------
	set textValues to {}
	if popCount > 0 then
		set allEls to {}
		tell application "System Events" to tell process appName
			try
				set allEls to entire contents of UI element 1 of menu bar item 1 of menu bar 2
			on error errMsg
				set end of outLines to "      note: entire contents 失败: " & errMsg
			end try
		end tell
		repeat with e in allEls
			try
				if (role of e as text) is "AXStaticText" then
					set v to (value of e) as text
					if v is not "" then set end of textValues to v
				end if
			end try
		end repeat
		-- 兜底：entire contents 没拿到文本时，退回读直接子元素
		if (count of textValues) is 0 then
			set directVals to {}
			tell application "System Events" to tell process appName
				try
					set directVals to value of every UI element of UI element 1 of menu bar item 1 of menu bar 2 whose role is "AXStaticText"
				end try
			end tell
			repeat with v in directVals
				try
					if (v as text) is not "" then set end of textValues to (v as text)
				end try
			end repeat
		end if
	end if

	set allText to my joinText(textValues)
	set todayStr to my todayLabel()
	set requiredTexts to {"AgentSpur", todayStr, "Cache 命中率", "24H 趋势", "深海小鲸"}
	set missingTexts to {}
	repeat with need in requiredTexts
		if allText does not contain (need as text) then set end of missingTexts to (need as text)
	end repeat
	set a4ok to ((count of textValues) > 0) and ((count of missingTexts) is 0)

	set end of outLines to "      今日断言串: " & todayStr
	if a4ok then
		set passCount to passCount + 1
		set end of outLines to "[PASS] A4 Popover 文本断言: 5/5 命中，共 " & (count of textValues) & " 条 AXStaticText"
	else
		set failCount to failCount + 1
		set end of outLines to "[FAIL] A4 Popover 文本断言: 命中 " & (5 - (count of missingTexts)) & "/5，共 " & (count of textValues) & " 条 AXStaticText"
		if (count of missingTexts) > 0 then
			set end of outLines to "      缺失: " & my joinText(missingTexts)
		end if
	end if
	set end of outLines to "      --- Popover AXStaticText (" & (count of textValues) & ") ---"
	repeat with tv in textValues
		set end of outLines to "      | " & (tv as text)
	end repeat
	set end of outLines to "      --- Popover AXStaticText end ---"

	-- ---------- A5 再 AXPress 一次，Popover 消失 ----------
	set a5ok to false
	set closeCount to -1
	set closeFocus to ""
	if popCount > 0 then
		try
			tell application "System Events" to tell process appName
				perform action "AXPress" of menu bar item 1 of menu bar 2
			end tell
		on error errMsg
			set end of outLines to "      关闭 AXPress 错误: " & errMsg
		end try
		delay 0.9
		tell application "System Events" to tell process appName
			try
				set closeCount to (count of UI elements of menu bar item 1 of menu bar 2)
			end try
			try
				set fe2 to value of attribute "AXFocusedUIElement"
				set closeFocus to (role of fe2 as text) & " / " & (description of fe2 as text)
			end try
		end tell
		set a5ok to (closeCount is 0) and (closeFocus does not contain "pop over") and (closeFocus does not contain "AXPopover")
	end if
	if a5ok then
		set passCount to passCount + 1
		set end of outLines to "[PASS] A5 再次 AXPress 后 Popover 消失: 子元素数=" & closeCount
	else
		set failCount to failCount + 1
		set end of outLines to "[FAIL] A5 再次 AXPress 后 Popover 未消失: 子元素数=" & closeCount
		set end of outLines to "      AXFocusedUIElement: " & closeFocus
	end if

	-- ---------- A6 清理：无论前面成败，最后 Popover 必须收起 ----------
	set cleanupCount to -1
	tell application "System Events" to tell process appName
		try
			set cleanupCount to (count of UI elements of menu bar item 1 of menu bar 2)
		end try
		if cleanupCount > 0 then
			try
				perform action "AXPress" of menu bar item 1 of menu bar 2
			end try
			delay 0.9
			try
				set cleanupCount to (count of UI elements of menu bar item 1 of menu bar 2)
			end try
		end if
	end tell
	set a6ok to (cleanupCount is 0)
	if a6ok then
		set passCount to passCount + 1
		set end of outLines to "[PASS] A6 收尾清理: Popover 已收起"
	else
		set failCount to failCount + 1
		set end of outLines to "[FAIL] A6 收尾清理: Popover 仍存在 (子元素数=" & cleanupCount & ")"
	end if

	-- ---------- 汇总 ----------
	set end of outLines to ""
	if failCount is 0 then
		set end of outLines to "RESULT: PASS 6/6"
	else
		set end of outLines to "RESULT: FAIL " & (6 - failCount) & "/6 (failed=" & failCount & ")"
	end if
	return my joinText(outLines)
end run

-- ================= 工具 handler =================

on joinText(lst)
	set oldDelims to text item delimiters
	set text item delimiters to linefeed
	set s to lst as text
	set text item delimiters to oldDelims
	return s
end joinText

on splitText(t, delim)
	set oldDelims to text item delimiters
	set text item delimiters to delim
	set parts to text items of (t as text)
	set text item delimiters to oldDelims
	return parts
end splitText

on trimText(t)
	set s to t as text
	try
		repeat while (count of s) > 0
			set c1 to character 1 of s
			if c1 is " " or c1 is tab or c1 is linefeed or c1 is return then
				if (count of s) is 1 then
					set s to ""
				else
					set s to text 2 thru -1 of s
				end if
			else
				exit repeat
			end if
		end repeat
		repeat while (count of s) > 0
			set cN to character -1 of s
			if cN is " " or cN is tab or cN is linefeed or cN is return then
				if (count of s) is 1 then
					set s to ""
				else
					set s to text 1 thru -2 of s
				end if
			else
				exit repeat
			end if
		end repeat
	on error
		return ""
	end try
	return s
end trimText

on listContains(lst, target)
	repeat with x in lst
		if (x as text) is (target as text) then return true
	end repeat
	return false
end listContains

on todayLabel()
	set d to current date
	set mm to month of d as integer
	set dd to day of d as integer
	return "今日 " & mm & "/" & dd
end todayLabel

on runShell(cmd)
	try
		return do shell script cmd
	on error
		return "unknown"
	end try
end runShell
