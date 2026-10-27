import Foundation
import SQLite3

struct OpenCodeDBSnapshot {
    let masters: [MasterSessionItem]
    let urgentSubTask: SubTaskItem?
    let topState: AgentRunState
    let topStateEnteredAtMs: Int64
    let weeklySeries: [DailyEfficiencyPoint]
    let totalSpentUsd: Double
    let dbExists: Bool
}

final class OpenCodeDBReader {
    let opencodeDirPath: String
    let dbPath: String

    // 缓存每个会话/子任务上一次的状态与进入该状态的时间戳，确保状态切换时计时自动从 0s 重置
    private var trackedStates: [String: (state: AgentRunState, enteredAtMs: Int64)] = [:]
    private var hasInitializedBaseline = false

    init() {
        let dir = ("~/.local/share/opencode" as NSString).expandingTildeInPath
        self.opencodeDirPath = dir
        self.dbPath = (dir as NSString).appendingPathComponent("opencode.db")
    }

    func readSnapshot(onTaskJustCompleted: ((String) -> Void)?) -> OpenCodeDBSnapshot {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        guard FileManager.default.fileExists(atPath: dbPath) else {
            return OpenCodeDBSnapshot(
                masters: [],
                urgentSubTask: nil,
                topState: .completed,
                topStateEnteredAtMs: nowMs,
                weeklySeries: buildEmptyWeeklySeries(),
                totalSpentUsd: 0.0,
                dbExists: false
            )
        }

        var db: OpaquePointer?
        let openFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(dbPath, &db, openFlags, nil) == SQLITE_OK, let db else {
            return OpenCodeDBSnapshot(
                masters: [],
                urgentSubTask: nil,
                topState: .completed,
                topStateEnteredAtMs: nowMs,
                weeklySeries: buildEmptyWeeklySeries(),
                totalSpentUsd: 0.0,
                dbExists: true
            )
        }
        defer { sqlite3_close(db) }

        // 避免阻塞 opencode TUI 的 WAL 写入，设置短 busy timeout
        sqlite3_busy_timeout(db, 80)

        let hasPermissionTable = tableExists(db: db, name: "permission")

        struct RawRow {
            let id: String
            let parentId: String?
            let title: String
            let directory: String
            let modelName: String
            let state: AgentRunState
            let dbTimeMs: Int64
            let durationSec: Int64?
            let dbRecordRef: String
        }

        var rawMap: [String: RawRow] = [:]
        var orderedIds: [String] = []

        let permSelect = hasPermissionTable
            ? "(SELECT COUNT(1) FROM permission pm WHERE pm.session_id = s.id)"
            : "0"

        let sql = """
        SELECT
            s.id,
            s.parent_id,
            COALESCE(NULLIF(s.title, ''), NULLIF(s.slug, ''), s.id) AS title,
            COALESCE(s.directory, '') AS directory,
            COALESCE(json_extract(s.model, '$.modelID'), 'deepseek-reasoner') AS model_name,
            COALESCE(s.time_updated, s.time_created, 0) AS sess_time,
            (SELECT p.id FROM part p WHERE p.session_id = s.id ORDER BY p.time_created DESC LIMIT 1) AS part_id,
            (SELECT json_extract(p.data, '$.type') FROM part p WHERE p.session_id = s.id ORDER BY p.time_created DESC LIMIT 1) AS part_type,
            (SELECT json_extract(p.data, '$.state.status') FROM part p WHERE p.session_id = s.id ORDER BY p.time_created DESC LIMIT 1) AS part_status,
            (SELECT p.time_created FROM part p WHERE p.session_id = s.id ORDER BY p.time_created DESC LIMIT 1) AS part_time,
            \(permSelect) AS perm_cnt,
            (SELECT (json_extract(m.data, '$.time.completed') - json_extract(m.data, '$.time.created')) / 1000
             FROM message m WHERE m.session_id = s.id AND json_extract(m.data, '$.time.completed') IS NOT NULL
             ORDER BY m.time_created DESC LIMIT 1) AS msg_dur_sec
        FROM session s
        WHERE s.time_archived IS NULL
        ORDER BY COALESCE(s.time_updated, s.time_created) DESC
        LIMIT 60;
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = colString(stmt, 0) ?? ""
                if id.isEmpty { continue }
                let rawParent = colString(stmt, 1)
                let parentId = (rawParent?.isEmpty == false) ? rawParent : nil
                let title = colString(stmt, 2) ?? id
                let directory = colString(stmt, 3) ?? ""
                let modelName = colString(stmt, 4) ?? "deepseek-reasoner"
                let sessTime = sqlite3_column_int64(stmt, 5)
                let partId = colString(stmt, 6) ?? "prt"
                let partType = colString(stmt, 7) ?? ""
                let partStatus = colString(stmt, 8) ?? ""
                let partTime = sqlite3_column_int64(stmt, 9)
                let msgDurSec: Int64? = sqlite3_column_type(stmt, 11) == SQLITE_NULL
                    ? nil
                    : max(1, sqlite3_column_int64(stmt, 11))

                let derivedState: AgentRunState
                let recordRef: String

                if partStatus == "error" {
                    derivedState = .error
                    recordRef = "part(\(partId)) · error"
                } else if partStatus == "pending" || partStatus == "awaiting_approval" {
                    derivedState = .confirm
                    recordRef = "permission(\(id)) · pending"
                } else if partType == "reasoning" {
                    derivedState = .thinking
                    recordRef = "part(\(partId)) · reasoning"
                } else if partType == "tool" || partType == "step-start" {
                    derivedState = .working
                    recordRef = "part(\(partId)) · \(partType)"
                } else {
                    derivedState = .completed
                    recordRef = "message · time.completed"
                }

                let dbTimestamp = partTime > 0 ? partTime : (sessTime > 0 ? sessTime : nowMs)

                // 核心逻辑：检测状态切换 -> 自动重置状态进入计时器，并在完成时触发静音通知
                let effectiveEnteredAtMs: Int64
                if let prev = trackedStates[id] {
                    if prev.state != derivedState {
                        effectiveEnteredAtMs = nowMs
                        trackedStates[id] = (derivedState, nowMs)
                        if hasInitializedBaseline && prev.state != .completed && derivedState == .completed {
                            onTaskJustCompleted?(title)
                        }
                    } else {
                        effectiveEnteredAtMs = prev.enteredAtMs
                    }
                } else {
                    effectiveEnteredAtMs = dbTimestamp
                    trackedStates[id] = (derivedState, dbTimestamp)
                }

                let row = RawRow(
                    id: id,
                    parentId: parentId,
                    title: title,
                    directory: directory,
                    modelName: modelName,
                    state: derivedState,
                    dbTimeMs: effectiveEnteredAtMs,
                    durationSec: msgDurSec,
                    dbRecordRef: recordRef
                )
                rawMap[id] = row
                orderedIds.append(id)
            }
            sqlite3_finalize(stmt)
        }

        hasInitializedBaseline = true

        // 组装 Master 与 Sub-Agent 层级树
        var masters: [MasterSessionItem] = []
        var allSubTasks: [SubTaskItem] = []

        for (idx, id) in orderedIds.enumerated() {
            guard let row = rawMap[id], row.parentId == nil else { continue }
            var subs: [SubTaskItem] = []

            for (cIdx, cid) in orderedIds.enumerated() {
                guard let child = rawMap[cid], child.parentId == id else { continue }
                let role = child.title.contains("@explore") ? "@explore" : "@general"
                let targetApp: TargetTerminalApp = (cIdx % 2 == 0) ? .opencodeTUI : .iterm2
                let sub = SubTaskItem(
                    id: child.id,
                    parentId: id,
                    title: child.title,
                    roleLabel: role,
                    directory: child.directory.isEmpty ? row.directory : child.directory,
                    state: child.state,
                    stateEnteredAtMs: child.dbTimeMs,
                    completedDurationSec: child.durationSec,
                    targetApp: targetApp,
                    itermTabIndex: cIdx % 4,
                    dbRecordRef: child.dbRecordRef
                )
                subs.append(sub)
                allSubTasks.append(sub)
            }

            let mTarget: TargetTerminalApp = (idx % 2 == 0) ? .opencodeTUI : .iterm2
            let master = MasterSessionItem(
                id: row.id,
                title: row.title,
                modelName: row.modelName,
                directory: row.directory,
                state: row.state,
                stateEnteredAtMs: row.dbTimeMs,
                completedDurationSec: row.durationSec,
                targetApp: mTarget,
                itermTabIndex: idx % 4,
                dbRecordRef: row.dbRecordRef,
                subTasks: subs
            )
            masters.append(master)
        }

        // 计算最紧急子任务（用于菜单栏 Hover Tooltip）
        let urgentSubTask = allSubTasks.max { a, b in
            if a.state.priority != b.state.priority {
                return a.state.priority < b.state.priority
            }
            return a.stateEnteredAtMs > b.stateEnteredAtMs
        }

        // 计算顶部菜单栏综合状态
        var topState: AgentRunState = .completed
        var topEnteredMs: Int64 = nowMs
        for m in masters {
            if m.state.priority > topState.priority {
                topState = m.state
                topEnteredMs = m.stateEnteredAtMs
            }
            for sub in m.subTasks where sub.state.priority > topState.priority {
                topState = sub.state
                topEnteredMs = sub.stateEnteredAtMs
            }
        }

        let spentUsd = queryTotalCostUsd(db: db)
        let weekly = queryWeeklyEfficiency(db: db)

        return OpenCodeDBSnapshot(
            masters: masters,
            urgentSubTask: urgentSubTask,
            topState: topState,
            topStateEnteredAtMs: topEnteredMs,
            weeklySeries: weekly,
            totalSpentUsd: spentUsd,
            dbExists: true
        )
    }

    private func queryTotalCostUsd(db: OpaquePointer) -> Double {
        var total = 0.0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COALESCE(SUM(cost), 0) FROM session;", -1, &stmt, nil) == SQLITE_OK, let stmt {
            if sqlite3_step(stmt) == SQLITE_ROW {
                total = sqlite3_column_double(stmt, 0)
            }
            sqlite3_finalize(stmt)
        }
        return total
    }

    private func queryWeeklyEfficiency(db: OpaquePointer) -> [DailyEfficiencyPoint] {
        var bucketCounts: [String: Int] = [:]
        var bucketDurSum: [String: Double] = [:]

        let sql = """
        SELECT
            strftime('%m/%d', time_created / 1000, 'unixepoch', 'localtime') AS day_key,
            COUNT(1) AS cnt,
            AVG(
                CASE
                    WHEN json_extract(data, '$.time.completed') IS NOT NULL
                         AND json_extract(data, '$.time.created') IS NOT NULL
                    THEN (json_extract(data, '$.time.completed') - json_extract(data, '$.time.created')) / 1000.0
                    ELSE NULL
                END
            ) AS avg_sec
        FROM message
        WHERE time_created >= (strftime('%s', 'now', '-6 days') * 1000)
          AND json_extract(data, '$.role') = 'assistant'
        GROUP BY day_key;
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let key = colString(stmt, 0) {
                    bucketCounts[key] = Int(sqlite3_column_int64(stmt, 1))
                    if sqlite3_column_type(stmt, 2) != SQLITE_NULL {
                        bucketDurSum[key] = max(1.0, sqlite3_column_double(stmt, 2))
                    }
                }
            }
            sqlite3_finalize(stmt)
        }

        return buildWeeklySeriesFromBuckets(counts: bucketCounts, avgDurations: bucketDurSum)
    }

    private func buildEmptyWeeklySeries() -> [DailyEfficiencyPoint] {
        return buildWeeklySeriesFromBuckets(counts: [:], avgDurations: [:])
    }

    private func buildWeeklySeriesFromBuckets(
        counts: [String: Int],
        avgDurations: [String: Double]
    ) -> [DailyEfficiencyPoint] {
        let cal = Calendar.current
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "MM/dd"
        let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

        var result: [DailyEfficiencyPoint] = []
        let today = Date()

        for offset in stride(from: 6, through: 0, by: -1) {
            let d = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let key = dateFmt.string(from: d)
            let wdIdx = max(0, min(6, cal.component(.weekday, from: d) - 1))
            let cnt = counts[key] ?? 0
            let avgSec = avgDurations[key] ?? 0.0
            let tph = cnt > 0 ? Double(cnt) / 2.0 : 0.0

            result.append(
                DailyEfficiencyPoint(
                    dayLabel: weekdayNames[wdIdx],
                    dateShort: key,
                    tasksPerHour: (tph * 10).rounded() / 10,
                    avgSeconds: avgSec.rounded(),
                    completedCount: cnt,
                    isToday: offset == 0
                )
            )
        }
        return result
    }

    private func tableExists(db: OpaquePointer, name: String) -> Bool {
        var exists = false
        var stmt: OpaquePointer?
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
            exists = (sqlite3_step(stmt) == SQLITE_ROW)
            sqlite3_finalize(stmt)
        }
        return exists
    }

    private func colString(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }
}
