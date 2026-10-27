import Foundation
import SQLite3

struct OpenCodeDBSnapshot: Equatable {
    let masters: [MasterSessionItem]
    let urgentSubTask: SubTaskItem?
    let topState: AgentRunState
    let topStateEnteredAtMs: Int64
    let todayHourlySeries: [TodayHourlyPoint]
    let billing: BillingTelemetrySummary
    let realWindows: [RealTerminalWindow]
    let activeDbFileName: String
    let dbExists: Bool
}

final class OpenCodeDBReader {
    let opencodeDirPath: String

    // 缓存每个会话/子任务上一次的状态与进入该状态的时间戳，确保状态切换时计时自动从 0s 重置
    private var trackedStates: [String: (state: AgentRunState, enteredAtMs: Int64)] = [:]
    private var hasInitializedBaseline = false

    init() {
        if let customEnv = ProcessInfo.processInfo.environment["OPENCODE_DB"], !customEnv.isEmpty {
            let expanded = (customEnv as NSString).expandingTildeInPath
            self.opencodeDirPath = (expanded as NSString).deletingLastPathComponent
        } else if let xdg = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !xdg.isEmpty {
            self.opencodeDirPath = ((xdg as NSString).expandingTildeInPath as NSString).appendingPathComponent("opencode")
        } else {
            self.opencodeDirPath = ("~/.local/share/opencode" as NSString).expandingTildeInPath
        }
    }

    /// 自动定位当前最新活跃的 opencode 数据库文件（支持 $OPENCODE_DB、opencode.db、opencode-stable.db 等通道库及 -wal 活跃度判断）
    func resolveActiveDatabasePath() -> String? {
        if let customEnv = ProcessInfo.processInfo.environment["OPENCODE_DB"], !customEnv.isEmpty {
            let expanded = (customEnv as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return expanded
            }
        }

        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: opencodeDirPath) else {
            let fallback = (opencodeDirPath as NSString).appendingPathComponent("opencode.db")
            return fm.fileExists(atPath: fallback) ? fallback : nil
        }

        let dbCandidates = items.filter { name in
            name.hasPrefix("opencode") && name.hasSuffix(".db")
        }
        guard !dbCandidates.isEmpty else { return nil }

        var bestPath: String?
        var bestMtime: Date = .distantPast

        for name in dbCandidates {
            let full = (opencodeDirPath as NSString).appendingPathComponent(name)
            let wal = full + "-wal"
            let dbDate = (try? fm.attributesOfItem(atPath: full)[.modificationDate] as? Date) ?? .distantPast
            let walDate = (try? fm.attributesOfItem(atPath: wal)[.modificationDate] as? Date) ?? .distantPast
            let latest = max(dbDate, walDate)
            if latest >= bestMtime {
                bestMtime = latest
                bestPath = full
            }
        }
        return bestPath
    }

    func readSnapshot(
        usdToCnyRate: Double,
        realWindows: [RealTerminalWindow],
        onTaskJustCompleted: ((String) -> Void)?
    ) -> OpenCodeDBSnapshot {
        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let cal = Calendar.current
        let todayStartDate = cal.startOfDay(for: now)
        let todayStartMs = Int64(todayStartDate.timeIntervalSince1970 * 1000)
        let currentHour = cal.component(.hour, from: now)

        let defaultTier = DeepSeekPricingEngine.classifyModel("deepseek-flash")
        let emptyBilling = BillingTelemetrySummary.empty(
            dateLabel: TimeFormatters.todayShortLabel(),
            tier: defaultTier
        )

        guard let dbPath = resolveActiveDatabasePath() else {
            return OpenCodeDBSnapshot(
                masters: [],
                urgentSubTask: nil,
                topState: .completed,
                topStateEnteredAtMs: nowMs,
                todayHourlySeries: buildEmptyHourlySeries(todayStartDate: todayStartDate, currentHour: currentHour),
                billing: emptyBilling,
                realWindows: realWindows,
                activeDbFileName: "opencode.db",
                dbExists: false
            )
        }

        let activeDbName = (dbPath as NSString).lastPathComponent

        var db: OpaquePointer?
        let rwFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX
        let roFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        if sqlite3_open_v2(dbPath, &db, rwFlags, nil) != SQLITE_OK {
            if db != nil { sqlite3_close(db); db = nil }
            guard sqlite3_open_v2(dbPath, &db, roFlags, nil) == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                return OpenCodeDBSnapshot(
                    masters: [],
                    urgentSubTask: nil,
                    topState: .completed,
                    topStateEnteredAtMs: nowMs,
                    todayHourlySeries: buildEmptyHourlySeries(todayStartDate: todayStartDate, currentHour: currentHour),
                    billing: emptyBilling,
                    realWindows: realWindows,
                    activeDbFileName: activeDbName,
                    dbExists: true
                )
            }
        }
        guard let db else {
            return OpenCodeDBSnapshot(
                masters: [],
                urgentSubTask: nil,
                topState: .completed,
                topStateEnteredAtMs: nowMs,
                todayHourlySeries: buildEmptyHourlySeries(todayStartDate: todayStartDate, currentHour: currentHour),
                billing: emptyBilling,
                realWindows: realWindows,
                activeDbFileName: activeDbName,
                dbExists: true
            )
        }
        defer { sqlite3_close(db) }

        _ = sqlite3_busy_timeout(db, 80)
        _ = sqlite3_exec(db, "PRAGMA query_only = ON;", nil, nil, nil)

        let sessionCols = tableColumns(db: db, table: "session")
        guard sessionCols.contains("id") else {
            return OpenCodeDBSnapshot(
                masters: [],
                urgentSubTask: nil,
                topState: .completed,
                topStateEnteredAtMs: nowMs,
                todayHourlySeries: buildEmptyHourlySeries(todayStartDate: todayStartDate, currentHour: currentHour),
                billing: emptyBilling,
                realWindows: realWindows,
                activeDbFileName: activeDbName,
                dbExists: true
            )
        }

        let hasMessageTable = tableExists(db: db, name: "message")
        let hasPartTable = tableExists(db: db, name: "part")
        let hasPermissionTable = tableExists(db: db, name: "permission")

        // Step 1: O(log N) 二分定位今日第一条 message 的 rowid，随后走主键范围扫描今日 100% 全量消息（零扫全表，同时不漏任何归档或超量会话！）
        let todayBillingScan = scanAllTodayMessagesViaRowIdBinarySearch(
            db: db,
            hasMessageTable: hasMessageTable,
            todayStartDate: todayStartDate,
            todayStartMs: todayStartMs,
            currentHour: currentHour,
            usdToCnyRate: usdToCnyRate
        )

        // Step 2: 收集今日产生过消息的所有会话 + 今日在 session/part 表活跃的会话
        var candidateSessionIds = todayBillingScan.touchedSessionIds
        let extraActiveIds = queryTodayTouchedSessionAndPartIds(
            db: db,
            sessionCols: sessionCols,
            hasPartTable: hasPartTable,
            todayStartMs: todayStartMs
        )
        candidateSessionIds.formUnion(extraActiveIds)

        if candidateSessionIds.isEmpty {
            candidateSessionIds = queryMostRecentFallbackSessionIds(db: db, sessionCols: sessionCols, limit: 8)
        }

        expandParentAndChildSessionIds(
            db: db,
            sessionCols: sessionCols,
            todayStartMs: todayStartMs,
            ids: &candidateSessionIds
        )

        // Step 3: 批量获取活跃会话元数据（包括已归档子任务以便把开销准确汇总到主会话，列表展示则过滤已归档顶层旧会话）
        let rawSessions = fetchSessionMetadata(
            db: db,
            sessionCols: sessionCols,
            sessionIds: Array(candidateSessionIds)
        )

        // Step 4: 对尚未被今日消息覆盖到的候选会话补齐最新一条消息，确保运行状态与模型名 100% 准确
        var latestMsgPerSession = todayBillingScan.latestMsgPerSession
        var lastCompletedDurPerSession = todayBillingScan.lastCompletedDurPerSession
        let missingMsgSessionIds = rawSessions.keys.filter { latestMsgPerSession[$0] == nil }
        if hasMessageTable && !missingMsgSessionIds.isEmpty {
            fetchLatestMessageForSessions(
                db: db,
                sessionIds: Array(missingMsgSessionIds),
                intoLatest: &latestMsgPerSession,
                intoDuration: &lastCompletedDurPerSession
            )
        }

        let sessionStates = deriveRunningStates(
            db: db,
            sessionIds: Array(rawSessions.keys),
            latestMsgPerSession: latestMsgPerSession,
            lastCompletedDurPerSession: lastCompletedDurPerSession,
            hasPartTable: hasPartTable,
            hasPermissionTable: hasPermissionTable,
            nowMs: nowMs
        )

        // Step 5: 处理每个会话的状态切换计时重置与完成通知
        struct ResolvedSession {
            let meta: RawSessionMeta
            var state: AgentRunState
            var enteredAtMs: Int64
            let durationSec: Int64?
            let modelName: String
            let agentRole: String
            let recordRef: String
            let hitTokens: Int64
            let missTokens: Int64
            let outTokens: Int64
            let costCny: Double
            let rawUsd: Double
            let cacheSavedCny: Double
            let requests: Int
            let cacheHitPct: Double
        }

        var resolvedMap: [String: ResolvedSession] = [:]
        for (id, meta) in rawSessions {
            let msgState = sessionStates[id]
            let derivedState = msgState?.state ?? .completed
            let rawStateTime = msgState?.stateTimeMs ?? meta.updatedMs
            let dbTimestamp = rawStateTime > 0 ? rawStateTime : nowMs

            let effectiveEnteredAtMs: Int64
            if let prev = trackedStates[id] {
                if prev.state != derivedState {
                    effectiveEnteredAtMs = nowMs
                    trackedStates[id] = (derivedState, nowMs)
                    if hasInitializedBaseline && prev.state != .completed && derivedState == .completed {
                        onTaskJustCompleted?(meta.title)
                    }
                } else {
                    effectiveEnteredAtMs = prev.enteredAtMs
                }
            } else {
                effectiveEnteredAtMs = dbTimestamp
                trackedStates[id] = (derivedState, dbTimestamp)
            }

            let sBill = todayBillingScan.perSessionBilling[id]
            resolvedMap[id] = ResolvedSession(
                meta: meta,
                state: derivedState,
                enteredAtMs: effectiveEnteredAtMs,
                durationSec: msgState?.lastCompletedDurationSec,
                modelName: msgState?.modelId ?? "deepseek-flash",
                agentRole: msgState?.agentName ?? "",
                recordRef: msgState?.recordRef ?? "session",
                hitTokens: sBill?.hitTokens ?? 0,
                missTokens: sBill?.missTokens ?? 0,
                outTokens: sBill?.outTokens ?? 0,
                costCny: sBill?.costCny ?? 0.0,
                rawUsd: sBill?.rawUsd ?? 0.0,
                cacheSavedCny: sBill?.cacheSavedCny ?? 0.0,
                requests: sBill?.requests ?? 0,
                cacheHitPct: sBill?.cacheHitPercent ?? 0.0
            )
        }

        hasInitializedBaseline = true

        // Step 6: 组装 Master 与 Sub-Agent 树，确保任何运行中的子任务绝对优先于已停止的报错子任务冒泡至 Master！
        let sortedIds = resolvedMap.keys.sorted { a, b in
            let ua = resolvedMap[a]?.meta.updatedMs ?? 0
            let ub = resolvedMap[b]?.meta.updatedMs ?? 0
            return ua > ub
        }

        var masters: [MasterSessionItem] = []
        var allSubTasks: [SubTaskItem] = []

        for id in sortedIds {
            guard let item = resolvedMap[id] else { continue }
            if let pid = item.meta.parentId, resolvedMap[pid] != nil {
                continue
            }
            // 已归档且当前不在运行的旧顶层会话不挤占列表（但其今日账单已在 Step 1 完整计入全局今日精算）
            if item.meta.isArchived && !item.state.isActiveRunning {
                continue
            }

            var subs: [SubTaskItem] = []
            var archivedChildrenCostCny = 0.0
            var archivedChildrenSavedCny = 0.0
            var archivedChildrenHit: Int64 = 0
            var archivedChildrenMiss: Int64 = 0
            var archivedChildrenOut: Int64 = 0
            var archivedChildrenReqs: Int = 0

            for cid in sortedIds {
                guard let child = resolvedMap[cid], child.meta.parentId == id else { continue }

                if child.meta.isArchived && !child.state.isActiveRunning {
                    archivedChildrenCostCny += child.costCny
                    archivedChildrenSavedCny += child.cacheSavedCny
                    archivedChildrenHit += child.hitTokens
                    archivedChildrenMiss += child.missTokens
                    archivedChildrenOut += child.outTokens
                    archivedChildrenReqs += child.requests
                    continue
                }

                let roleStr: String
                if !child.agentRole.isEmpty {
                    roleStr = "@\(child.agentRole)"
                } else if child.meta.title.contains("@explore") {
                    roleStr = "@explore"
                } else if child.meta.title.contains("@dev") {
                    roleStr = "@dev"
                } else {
                    roleStr = "@subagent"
                }

                let effDir = child.meta.directory.isEmpty ? item.meta.directory : child.meta.directory
                let matchedWin = TerminalBridge.matchSessionToWindow(
                    directory: effDir,
                    sessionTitle: child.meta.title,
                    windows: realWindows
                )

                let sub = SubTaskItem(
                    id: child.meta.id,
                    parentId: id,
                    title: child.meta.title,
                    roleLabel: roleStr,
                    directory: effDir,
                    state: child.state,
                    stateEnteredAtMs: child.enteredAtMs,
                    completedDurationSec: child.durationSec,
                    matchedWindow: matchedWin,
                    dbRecordRef: child.recordRef,
                    spurCostCny: child.costCny,
                    opencodeRawUsd: child.rawUsd,
                    requestCount: child.requests,
                    inputCacheHitTokens: child.hitTokens,
                    inputCacheMissTokens: child.missTokens,
                    outputTokens: child.outTokens,
                    cacheSavedCny: child.cacheSavedCny,
                    cacheHitPercent: child.cacheHitPct
                )
                subs.append(sub)
                allSubTasks.append(sub)
            }

            // 将子任务按“运行中排最前 -> 最新时间”排序
            subs.sort { a, b in
                if a.state.isActiveRunning != b.state.isActiveRunning {
                    return a.state.isActiveRunning && !b.state.isActiveRunning
                }
                if a.state.activeFirstRank != b.state.activeFirstRank {
                    return a.state.activeFirstRank > b.state.activeFirstRank
                }
                return a.stateEnteredAtMs > b.stateEnteredAtMs
            }

            // 冒泡逻辑：只要任一子任务正在运行 (.confirm=50 / .working=40 / .thinking=30)，就绝对覆盖主会话或其它兄弟子任务的旧 .error(20)！
            var effectiveMasterState = item.state
            var effectiveMasterEnteredMs = item.enteredAtMs
            var bestRank = effectiveMasterState.activeFirstRank
            for sub in subs {
                let r = sub.state.activeFirstRank
                if r > bestRank {
                    bestRank = r
                    effectiveMasterState = sub.state
                    effectiveMasterEnteredMs = sub.stateEnteredAtMs
                }
            }

            let masterMatchedWin = TerminalBridge.matchSessionToWindow(
                directory: item.meta.directory,
                sessionTitle: item.meta.title,
                windows: realWindows
            )

            let combinedHit = item.hitTokens + archivedChildrenHit + subs.reduce(0) { $0 + $1.inputCacheHitTokens }
            let combinedMiss = item.missTokens + archivedChildrenMiss + subs.reduce(0) { $0 + $1.inputCacheMissTokens }
            let combinedOut = item.outTokens + archivedChildrenOut + subs.reduce(0) { $0 + $1.outputTokens }
            let combinedCost = item.costCny + archivedChildrenCostCny + subs.reduce(0.0) { $0 + $1.spurCostCny }
            let combinedSaved = item.cacheSavedCny + archivedChildrenSavedCny + subs.reduce(0.0) { $0 + $1.cacheSavedCny }
            let combinedReqs = item.requests + archivedChildrenReqs + subs.reduce(0) { $0 + $1.requestCount }
            let totalCombinedIn = combinedHit + combinedMiss
            let combinedHitPct = totalCombinedIn > 0
                ? (Double(combinedHit) / Double(totalCombinedIn)) * 100.0
                : item.cacheHitPct

            let master = MasterSessionItem(
                id: item.meta.id,
                title: item.meta.title,
                modelName: item.modelName,
                directory: item.meta.directory,
                state: effectiveMasterState,
                stateEnteredAtMs: effectiveMasterEnteredMs,
                completedDurationSec: item.durationSec,
                matchedWindow: masterMatchedWin,
                dbRecordRef: item.recordRef,
                ownCostCny: item.costCny,
                ownOpenCodeUsd: item.rawUsd,
                spurCostCny: combinedCost,
                requestCount: combinedReqs,
                inputCacheHitTokens: combinedHit,
                inputCacheMissTokens: combinedMiss,
                outputTokens: combinedOut,
                cacheSavedCny: combinedSaved,
                cacheHitPercent: combinedHitPct,
                subTasks: subs
            )
            masters.append(master)
        }

        // 将正在运行的会话排在最前
        masters.sort { a, b in
            if a.state.isActiveRunning != b.state.isActiveRunning {
                return a.state.isActiveRunning && !b.state.isActiveRunning
            }
            if a.state.activeFirstRank != b.state.activeFirstRank {
                return a.state.activeFirstRank > b.state.activeFirstRank
            }
            return a.stateEnteredAtMs > b.stateEnteredAtMs
        }

        let urgentSubTask: SubTaskItem? = allSubTasks.max { a, b in
            if a.state.activeFirstRank != b.state.activeFirstRank {
                return a.state.activeFirstRank < b.state.activeFirstRank
            }
            return a.stateEnteredAtMs < b.stateEnteredAtMs
        } ?? masters.first(where: { $0.state != .completed }).map { m in
            SubTaskItem(
                id: m.id,
                parentId: m.id,
                title: m.title,
                roleLabel: "@master",
                directory: m.directory,
                state: m.state,
                stateEnteredAtMs: m.stateEnteredAtMs,
                completedDurationSec: m.completedDurationSec,
                matchedWindow: m.matchedWindow,
                dbRecordRef: m.dbRecordRef,
                spurCostCny: m.spurCostCny,
                opencodeRawUsd: m.ownOpenCodeUsd,
                requestCount: m.requestCount,
                inputCacheHitTokens: m.inputCacheHitTokens,
                inputCacheMissTokens: m.inputCacheMissTokens,
                outputTokens: m.outputTokens,
                cacheSavedCny: m.cacheSavedCny,
                cacheHitPercent: m.cacheHitPercent
            )
        }

        var topState: AgentRunState = .completed
        var topEnteredMs: Int64 = nowMs
        var bestTopRank = -1
        for m in masters {
            let r = m.state.activeFirstRank
            if r > bestTopRank {
                bestTopRank = r
                topState = m.state
                topEnteredMs = m.stateEnteredAtMs
            }
        }

        return OpenCodeDBSnapshot(
            masters: masters,
            urgentSubTask: urgentSubTask,
            topState: topState,
            topStateEnteredAtMs: topEnteredMs,
            todayHourlySeries: todayBillingScan.hourlyPoints,
            billing: todayBillingScan.globalBilling,
            realWindows: realWindows,
            activeDbFileName: activeDbName,
            dbExists: true
        )
    }

    // MARK: - O(log N) RowId Binary Search + Exact Token Deduplication Engine

    private struct RawSessionMeta {
        let id: String
        let parentId: String?
        let title: String
        let directory: String
        let updatedMs: Int64
        let isArchived: Bool
    }

    private struct LatestMsgRecord {
        let msgId: String
        let role: String
        let createdMs: Int64
        let completedMs: Int64?
        let hasError: Bool
        let modelId: String
        let agentName: String
    }

    private struct SessionRuntimeInfo {
        var state: AgentRunState
        var stateTimeMs: Int64
        var lastCompletedDurationSec: Int64?
        var modelId: String
        var agentName: String
        var recordRef: String
    }

    private struct SessionBillingAcc {
        var hitTokens: Int64 = 0
        var missTokens: Int64 = 0
        var outTokens: Int64 = 0
        var requests: Int = 0
        var costCny: Double = 0.0
        var rawUsd: Double = 0.0
        var cacheSavedCny: Double = 0.0

        var cacheHitPercent: Double {
            let tot = hitTokens + missTokens
            return tot > 0 ? (Double(hitTokens) / Double(tot)) * 100.0 : 0.0
        }
    }

    private struct TodayMessageScanResult {
        let globalBilling: BillingTelemetrySummary
        let perSessionBilling: [String: SessionBillingAcc]
        let touchedSessionIds: Set<String>
        let latestMsgPerSession: [String: LatestMsgRecord]
        let lastCompletedDurPerSession: [String: Int64]
        let hourlyPoints: [TodayHourlyPoint]
    }

    /// 用 SQLite B-Tree 主键 rowid 二分查找定位今日 00:00 起始行（耗时 <0.1ms），避免全表扫描同时保证今日全量消息 0 遗漏
    private func findFirstMessageRowIdOnOrAfter(db: OpaquePointer, targetMs: Int64) -> Int64 {
        var minRow: Int64 = 1
        var maxRow: Int64 = 0
        var mmStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT MIN(rowid), MAX(rowid) FROM message;", -1, &mmStmt, nil) == SQLITE_OK, let mmStmt {
            if sqlite3_step(mmStmt) == SQLITE_ROW {
                minRow = max(1, sqlite3_column_int64(mmStmt, 0))
                maxRow = sqlite3_column_int64(mmStmt, 1)
            }
            sqlite3_finalize(mmStmt)
        }
        guard maxRow >= minRow else { return 1 }

        var lo = minRow
        var hi = maxRow
        var ans = maxRow + 1

        let probeSql = """
        SELECT rowid, COALESCE(time_created, json_extract(data, '$.time.created'), 0)
        FROM message WHERE rowid >= ? ORDER BY rowid ASC LIMIT 1;
        """
        var probeStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, probeSql, -1, &probeStmt, nil) == SQLITE_OK, let probeStmt else {
            return max(1, maxRow - 5000)
        }
        defer { sqlite3_finalize(probeStmt) }

        while lo <= hi {
            let mid = lo + (hi - lo) / 2
            sqlite3_reset(probeStmt)
            sqlite3_clear_bindings(probeStmt)
            sqlite3_bind_int64(probeStmt, 1, mid)

            if sqlite3_step(probeStmt) == SQLITE_ROW {
                let actualRow = sqlite3_column_int64(probeStmt, 0)
                let rowMs = normalizeToMs(sqlite3_column_int64(probeStmt, 1))
                if rowMs >= targetMs {
                    ans = mid
                    hi = mid - 1
                } else {
                    lo = max(mid + 1, actualRow + 1)
                }
            } else {
                hi = mid - 1
            }
        }

        // 回退 800 行缓冲，防止并发子代理乱序落库漏算今日临界点消息
        return max(1, ans - 800)
    }

    private func scanAllTodayMessagesViaRowIdBinarySearch(
        db: OpaquePointer,
        hasMessageTable: Bool,
        todayStartDate: Date,
        todayStartMs: Int64,
        currentHour: Int,
        usdToCnyRate: Double
    ) -> TodayMessageScanResult {
        guard hasMessageTable else {
            let defaultTier = DeepSeekPricingEngine.classifyModel("deepseek-flash")
            return TodayMessageScanResult(
                globalBilling: BillingTelemetrySummary.empty(dateLabel: TimeFormatters.todayShortLabel(), tier: defaultTier),
                perSessionBilling: [:],
                touchedSessionIds: [],
                latestMsgPerSession: [:],
                lastCompletedDurPerSession: [:],
                hourlyPoints: buildEmptyHourlySeries(todayStartDate: todayStartDate, currentHour: currentHour)
            )
        }

        let startRowId = findFirstMessageRowIdOnOrAfter(db: db, targetMs: todayStartMs)

        var totalHit: Int64 = 0
        var totalMiss: Int64 = 0
        var totalCacheWrite: Int64 = 0
        var totalOut: Int64 = 0
        var totalReasoning: Int64 = 0
        var totalReqs: Int = 0
        var offPeakReqs: Int = 0
        var totalSpurCny: Double = 0.0
        var totalPeakCostCny: Double = 0.0
        var totalOffPeakCostCny: Double = 0.0
        var totalHitCostCny: Double = 0.0
        var totalMissCostCny: Double = 0.0
        var totalOutCostCny: Double = 0.0
        var totalCacheSavedCny: Double = 0.0
        var totalOffPeakSavedCny: Double = 0.0
        var totalOpenCodeUsd: Double = 0.0
        var modelFreq: [String: Int] = [:]

        var perSessionBilling: [String: SessionBillingAcc] = [:]
        var touchedSessionIds = Set<String>()
        var latestMsgPerSession: [String: LatestMsgRecord] = [:]
        var lastCompletedDurPerSession: [String: Int64] = [:]

        var hourlyReqBuckets = Array(repeating: 0, count: 24)
        var hourlyCostBuckets = Array(repeating: 0.0, count: 24)
        var hourlyHitBuckets = Array(repeating: Int64(0), count: 24)
        var hourlyTotalInBuckets = Array(repeating: Int64(0), count: 24)

        let sql = """
        SELECT
            id,
            session_id,
            COALESCE(time_created, json_extract(data, '$.time.created'), 0) AS created_t,
            COALESCE(json_extract(data, '$.role'), '') AS role,
            json_extract(data, '$.time.completed') AS completed_t,
            CASE WHEN json_extract(data, '$.error') IS NOT NULL THEN 1 ELSE 0 END AS has_err,
            COALESCE(
                json_extract(data, '$.modelID'),
                json_extract(data, '$.model.modelID'),
                'deepseek-flash'
            ) AS model_id,
            COALESCE(json_extract(data, '$.agent'), json_extract(data, '$.mode'), '') AS agent_name,
            COALESCE(json_extract(data, '$.tokens.total'), 0) AS tok_total,
            COALESCE(json_extract(data, '$.tokens.cache.read'), 0) AS cache_hit,
            COALESCE(json_extract(data, '$.tokens.input'), 0) AS raw_in,
            COALESCE(json_extract(data, '$.tokens.cache.write'), 0) AS cache_write,
            COALESCE(json_extract(data, '$.tokens.output'), 0) AS raw_out,
            COALESCE(json_extract(data, '$.tokens.reasoning'), 0) AS raw_reas,
            COALESCE(json_extract(data, '$.cost'), 0.0) AS raw_usd
        FROM message
        WHERE rowid >= ?
        ORDER BY rowid ASC;
        """

        var stmt: OpaquePointer?
        let localCal = Calendar.current
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            sqlite3_bind_int64(stmt, 1, startRowId)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let msgId = colString(stmt, 0) ?? ""
                let sessId = colString(stmt, 1) ?? ""
                if sessId.isEmpty { continue }

                let createdMs = normalizeToMs(sqlite3_column_int64(stmt, 2))
                let role = colString(stmt, 3) ?? ""
                let completedMs: Int64? = sqlite3_column_type(stmt, 4) == SQLITE_NULL
                    ? nil
                    : normalizeToMs(sqlite3_column_int64(stmt, 4))
                let hasErr = sqlite3_column_int64(stmt, 5) != 0
                let modelId = colString(stmt, 6) ?? "deepseek-flash"
                let agentName = colString(stmt, 7) ?? ""

                latestMsgPerSession[sessId] = LatestMsgRecord(
                    msgId: msgId,
                    role: role,
                    createdMs: createdMs,
                    completedMs: completedMs,
                    hasError: hasErr,
                    modelId: modelId,
                    agentName: agentName
                )

                if let compMs = completedMs, createdMs > 0, compMs >= createdMs {
                    lastCompletedDurPerSession[sessId] = max(1, (compMs - createdMs) / 1000)
                }

                // 严格只统计【今日 00:00 起】产生的消息
                guard createdMs >= todayStartMs else { continue }
                touchedSessionIds.insert(sessId)

                guard role == "assistant" else { continue }

                let tokTotal = max(0, sqlite3_column_int64(stmt, 8))
                let hit = max(0, sqlite3_column_int64(stmt, 9))
                let rawIn = max(0, sqlite3_column_int64(stmt, 10))
                let cacheWrite = max(0, sqlite3_column_int64(stmt, 11))
                let rawOut = max(0, sqlite3_column_int64(stmt, 12))
                let rawReas = max(0, sqlite3_column_int64(stmt, 13))
                let rawUsd = max(0.0, sqlite3_column_double(stmt, 14))

                // 精确推导未命中输入 Token (防止个别适配器未从 input 扣除 cache.read 造成重复计费)
                let uncachedIn: Int64
                if tokTotal > 0 && hit > 0 && rawIn >= hit {
                    let sumIfExcluded = hit + rawIn + cacheWrite + rawOut
                    let sumIfIncluded = rawIn + cacheWrite + rawOut
                    if abs(sumIfIncluded - tokTotal) < abs(sumIfExcluded - tokTotal) {
                        uncachedIn = rawIn - hit
                    } else {
                        uncachedIn = rawIn
                    }
                } else {
                    uncachedIn = rawIn
                }
                let miss = uncachedIn + cacheWrite

                // 精确推导计费输出 Token：
                // OpenCode 1.18+ 在 getUsage() 中已将 output 与 reasoning 拆分为互斥桶，且 tokens.total = hit + miss + output + reasoning；
                // 若遇到自定义兼容网关在 output 中已含 reasoning 但 total 仍按真实总长返回，通过与 tokens.total 对账自动去重，绝不双计！
                let promptSum = hit + miss
                let billedOut: Int64
                if tokTotal > promptSum {
                    let impliedOut = tokTotal - promptSum
                    let errOutOnly = abs(rawOut - impliedOut)
                    let errOutPlusReas = abs((rawOut + rawReas) - impliedOut)
                    billedOut = (errOutOnly < errOutPlusReas) ? rawOut : (rawOut + rawReas)
                } else {
                    billedOut = rawOut + rawReas
                }

                guard hit > 0 || miss > 0 || billedOut > 0 || rawUsd > 0 else { continue }

                let bd = DeepSeekPricingEngine.calculateRequestCostBreakdown(
                    rawModelId: modelId,
                    timestampMs: createdMs,
                    inputCacheHitTokens: hit,
                    inputCacheMissTokens: miss,
                    outputTokens: billedOut,
                    opencodeFallbackUsd: rawUsd,
                    usdToCnyRate: usdToCnyRate
                )

                totalHit += hit
                totalMiss += miss
                totalCacheWrite += cacheWrite
                totalOut += billedOut
                totalReasoning += min(billedOut, rawReas)
                totalReqs += 1
                if bd.isOffPeak {
                    offPeakReqs += 1
                    totalOffPeakCostCny += bd.totalCostCny
                } else {
                    totalPeakCostCny += bd.totalCostCny
                }
                totalSpurCny += bd.totalCostCny
                totalHitCostCny += bd.hitCostCny
                totalMissCostCny += bd.missCostCny
                totalOutCostCny += bd.outputCostCny
                totalCacheSavedCny += bd.cacheSavedCny
                totalOffPeakSavedCny += bd.offPeakSavedCny
                totalOpenCodeUsd += rawUsd
                modelFreq[modelId, default: 0] += 1

                var acc = perSessionBilling[sessId] ?? SessionBillingAcc()
                acc.hitTokens += hit
                acc.missTokens += miss
                acc.outTokens += billedOut
                acc.requests += 1
                acc.costCny += bd.totalCostCny
                acc.rawUsd += rawUsd
                acc.cacheSavedCny += bd.cacheSavedCny
                perSessionBilling[sessId] = acc

                let msgDate = Date(timeIntervalSince1970: Double(createdMs) / 1000.0)
                let hr = max(0, min(23, localCal.component(.hour, from: msgDate)))
                hourlyReqBuckets[hr] += 1
                hourlyCostBuckets[hr] += bd.totalCostCny
                hourlyHitBuckets[hr] += hit
                hourlyTotalInBuckets[hr] += (hit + miss)
            }
            sqlite3_finalize(stmt)
        }

        let dominantModel = modelFreq.max(by: { $0.value < $1.value })?.key ?? "deepseek-flash"
        let tier = DeepSeekPricingEngine.classifyModel(dominantModel)

        let globalBilling = BillingTelemetrySummary(
            dateLabel: TimeFormatters.todayShortLabel(),
            dominantModelId: tier.canonicalModelId,
            dominantModelSpec: tier.specSummary,
            inputCacheHitTokens: totalHit,
            inputCacheMissTokens: totalMiss,
            cacheWriteTokens: totalCacheWrite,
            outputTokens: totalOut,
            reasoningTokens: totalReasoning,
            requestCount: totalReqs,
            offPeakRequestCount: offPeakReqs,
            spurCostCny: totalSpurCny,
            peakCostCny: totalPeakCostCny,
            offPeakCostCny: totalOffPeakCostCny,
            cacheHitCostCny: totalHitCostCny,
            cacheMissCostCny: totalMissCostCny,
            outputCostCny: totalOutCostCny,
            cacheSavedCny: totalCacheSavedCny,
            offPeakSavedCny: totalOffPeakSavedCny,
            opencodeRawUsd: totalOpenCodeUsd
        )

        let hourlyPoints: [TodayHourlyPoint] = (0..<24).map { hr in
            let totIn = hourlyTotalInBuckets[hr]
            let hitPct = totIn > 0 ? (Double(hourlyHitBuckets[hr]) / Double(totIn)) * 100.0 : 0.0
            let hourDate = todayStartDate.addingTimeInterval(Double(hr) * 3600.0 + 60.0)
            let isPeak = (DeepSeekPricingEngine.priceWindow(at: hourDate) == .peak)
            return TodayHourlyPoint(
                hour: hr,
                hourLabel: String(format: "%02d", hr),
                requestCount: hourlyReqBuckets[hr],
                costCny: hourlyCostBuckets[hr],
                cacheHitPercent: hitPct,
                isPeakHour: isPeak,
                isCurrentHour: hr == currentHour
            )
        }

        return TodayMessageScanResult(
            globalBilling: globalBilling,
            perSessionBilling: perSessionBilling,
            touchedSessionIds: touchedSessionIds,
            latestMsgPerSession: latestMsgPerSession,
            lastCompletedDurPerSession: lastCompletedDurPerSession,
            hourlyPoints: hourlyPoints
        )
    }

    private func queryTodayTouchedSessionAndPartIds(
        db: OpaquePointer,
        sessionCols: Set<String>,
        hasPartTable: Bool,
        todayStartMs: Int64
    ) -> Set<String> {
        var ids = Set<String>()
        let todayStartSec = todayStartMs / 1000

        if sessionCols.contains("time_updated") && sessionCols.contains("time_created") {
            let archivedClause = sessionCols.contains("time_archived") ? "AND time_archived IS NULL" : ""
            let sql = """
            SELECT id FROM session
            WHERE (time_updated >= ? OR time_created >= ? OR (time_updated BETWEEN ? AND ?))
            \(archivedClause);
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
                sqlite3_bind_int64(stmt, 1, todayStartMs)
                sqlite3_bind_int64(stmt, 2, todayStartMs)
                sqlite3_bind_int64(stmt, 3, todayStartSec)
                sqlite3_bind_int64(stmt, 4, todayStartSec + 86400 * 2)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let sId = colString(stmt, 0), !sId.isEmpty {
                        ids.insert(sId)
                    }
                }
                sqlite3_finalize(stmt)
            }
        }

        if hasPartTable {
            let sql = "SELECT session_id, time_created FROM part ORDER BY rowid DESC LIMIT 80;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let rawT = normalizeToMs(sqlite3_column_int64(stmt, 1))
                    if rawT >= todayStartMs, let sId = colString(stmt, 0), !sId.isEmpty {
                        ids.insert(sId)
                    }
                }
                sqlite3_finalize(stmt)
            }
        }

        return ids
    }

    private func queryMostRecentFallbackSessionIds(
        db: OpaquePointer,
        sessionCols: Set<String>,
        limit: Int
    ) -> Set<String> {
        var ids = Set<String>()
        let archivedClause = sessionCols.contains("time_archived") ? "WHERE time_archived IS NULL" : ""
        let orderCol = sessionCols.contains("time_updated") ? "time_updated" : "rowid"
        let sql = "SELECT id FROM session \(archivedClause) ORDER BY \(orderCol) DESC LIMIT \(limit);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let id = colString(stmt, 0), !id.isEmpty {
                    ids.insert(id)
                }
            }
            sqlite3_finalize(stmt)
        }
        return ids
    }

    private func expandParentAndChildSessionIds(
        db: OpaquePointer,
        sessionCols: Set<String>,
        todayStartMs: Int64,
        ids: inout Set<String>
    ) {
        guard !ids.isEmpty, sessionCols.contains("parent_id") else { return }
        // 两轮父子闭包扩展，确保 Master <-> SubAgent 完整树结构不丢失
        for _ in 0..<2 {
            let beforeCount = ids.count
            let quoted = ids.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }.joined(separator: ",")
            let sql = """
            SELECT id, parent_id, COALESCE(time_updated, time_created, 0) FROM session
            WHERE id IN (\(quoted)) OR parent_id IN (\(quoted));
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let id = colString(stmt, 0), !id.isEmpty {
                        let t = normalizeToMs(sqlite3_column_int64(stmt, 2))
                        if ids.contains(id) || t >= todayStartMs {
                            ids.insert(id)
                        }
                    }
                    if let pid = colString(stmt, 1), !pid.isEmpty {
                        ids.insert(pid)
                    }
                }
                sqlite3_finalize(stmt)
            }
            if ids.count == beforeCount { break }
        }
    }

    private func fetchSessionMetadata(
        db: OpaquePointer,
        sessionCols: Set<String>,
        sessionIds: [String]
    ) -> [String: RawSessionMeta] {
        guard !sessionIds.isEmpty else { return [:] }
        let quoted = sessionIds.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }.joined(separator: ",")

        let parentExpr = sessionCols.contains("parent_id") ? "parent_id" : "NULL"
        let hasDataJson = sessionCols.contains("data")

        let titleExpr: String
        if sessionCols.contains("title") && sessionCols.contains("slug") {
            titleExpr = "COALESCE(NULLIF(title, ''), NULLIF(slug, ''), id)"
        } else if sessionCols.contains("title") {
            titleExpr = "COALESCE(NULLIF(title, ''), id)"
        } else if hasDataJson {
            titleExpr = "COALESCE(json_extract(data, '$.title'), id)"
        } else {
            titleExpr = "id"
        }

        let dirExpr: String
        if sessionCols.contains("directory") {
            dirExpr = "COALESCE(directory, '')"
        } else if hasDataJson {
            dirExpr = "COALESCE(json_extract(data, '$.directory'), '')"
        } else {
            dirExpr = "''"
        }

        let timeExpr: String
        if sessionCols.contains("time_updated") && sessionCols.contains("time_created") {
            timeExpr = "COALESCE(time_updated, time_created, 0)"
        } else if sessionCols.contains("time_created") {
            timeExpr = "COALESCE(time_created, 0)"
        } else {
            timeExpr = "0"
        }

        let archivedExpr = sessionCols.contains("time_archived")
            ? "CASE WHEN time_archived IS NOT NULL THEN 1 ELSE 0 END"
            : "0"

        let sql = "SELECT id, \(parentExpr), \(titleExpr), \(dirExpr), \(timeExpr), \(archivedExpr) FROM session WHERE id IN (\(quoted));"
        var map: [String: RawSessionMeta] = [:]
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let id = colString(stmt, 0), !id.isEmpty else { continue }
                let rawPid = colString(stmt, 1)
                let pid = (rawPid?.isEmpty == false) ? rawPid : nil
                let title = colString(stmt, 2) ?? id
                let dir = colString(stmt, 3) ?? ""
                let upd = normalizeToMs(sqlite3_column_int64(stmt, 4))
                let isArch = sqlite3_column_int64(stmt, 5) != 0
                map[id] = RawSessionMeta(
                    id: id,
                    parentId: pid,
                    title: title,
                    directory: dir,
                    updatedMs: upd,
                    isArchived: isArch
                )
            }
            sqlite3_finalize(stmt)
        }
        return map
    }

    private func fetchLatestMessageForSessions(
        db: OpaquePointer,
        sessionIds: [String],
        intoLatest: inout [String: LatestMsgRecord],
        intoDuration: inout [String: Int64]
    ) {
        let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let sql = """
        SELECT
            id,
            COALESCE(time_created, json_extract(data, '$.time.created'), 0),
            COALESCE(json_extract(data, '$.role'), ''),
            json_extract(data, '$.time.completed'),
            CASE WHEN json_extract(data, '$.error') IS NOT NULL THEN 1 ELSE 0 END,
            COALESCE(json_extract(data, '$.modelID'), json_extract(data, '$.model.modelID'), 'deepseek-flash'),
            COALESCE(json_extract(data, '$.agent'), json_extract(data, '$.mode'), '')
        FROM message
        WHERE session_id = ?
        ORDER BY rowid DESC LIMIT 1;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }

        for sId in sessionIds {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            _ = sId.withCString { cStr in
                sqlite3_bind_text(stmt, 1, cStr, -1, sqliteTransient)
            }
            if sqlite3_step(stmt) == SQLITE_ROW {
                let mId = colString(stmt, 0) ?? ""
                let createdMs = normalizeToMs(sqlite3_column_int64(stmt, 1))
                let role = colString(stmt, 2) ?? ""
                let completedMs: Int64? = sqlite3_column_type(stmt, 3) == SQLITE_NULL
                    ? nil
                    : normalizeToMs(sqlite3_column_int64(stmt, 3))
                let hasErr = sqlite3_column_int64(stmt, 4) != 0
                let modelId = colString(stmt, 5) ?? "deepseek-flash"
                let agentName = colString(stmt, 6) ?? ""

                intoLatest[sId] = LatestMsgRecord(
                    msgId: mId,
                    role: role,
                    createdMs: createdMs,
                    completedMs: completedMs,
                    hasError: hasErr,
                    modelId: modelId,
                    agentName: agentName
                )
                if let compMs = completedMs, createdMs > 0, compMs >= createdMs {
                    intoDuration[sId] = max(1, (compMs - createdMs) / 1000)
                }
            }
        }
    }

    private func deriveRunningStates(
        db: OpaquePointer,
        sessionIds: [String],
        latestMsgPerSession: [String: LatestMsgRecord],
        lastCompletedDurPerSession: [String: Int64],
        hasPartTable: Bool,
        hasPermissionTable: Bool,
        nowMs: Int64
    ) -> [String: SessionRuntimeInfo] {
        var pendingPermissionSessions = Set<String>()
        if hasPermissionTable && !sessionIds.isEmpty {
            let quoted = sessionIds.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }.joined(separator: ",")
            var pStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT DISTINCT session_id FROM permission WHERE session_id IN (\(quoted));", -1, &pStmt, nil) == SQLITE_OK, let pStmt {
                while sqlite3_step(pStmt) == SQLITE_ROW {
                    if let sId = colString(pStmt, 0) {
                        pendingPermissionSessions.insert(sId)
                    }
                }
                sqlite3_finalize(pStmt)
            }
        }

        var sessionStates: [String: SessionRuntimeInfo] = [:]
        let activeStaleThresholdMs: Int64 = 45 * 60 * 1000

        for (sessId, lastMsg) in latestMsgPerSession {
            let durSec = lastCompletedDurPerSession[sessId]

            if pendingPermissionSessions.contains(sessId) {
                sessionStates[sessId] = SessionRuntimeInfo(
                    state: .confirm,
                    stateTimeMs: lastMsg.createdMs,
                    lastCompletedDurationSec: durSec,
                    modelId: lastMsg.modelId,
                    agentName: lastMsg.agentName,
                    recordRef: "permission · pending"
                )
                continue
            }

            if lastMsg.hasError {
                sessionStates[sessId] = SessionRuntimeInfo(
                    state: .error,
                    stateTimeMs: lastMsg.completedMs ?? lastMsg.createdMs,
                    lastCompletedDurationSec: durSec,
                    modelId: lastMsg.modelId,
                    agentName: lastMsg.agentName,
                    recordRef: "message(\(lastMsg.msgId.prefix(10))) · error"
                )
                continue
            }

            if lastMsg.role == "user" && (nowMs - lastMsg.createdMs) < 15 * 60 * 1000 {
                sessionStates[sessId] = SessionRuntimeInfo(
                    state: .thinking,
                    stateTimeMs: lastMsg.createdMs,
                    lastCompletedDurationSec: durSec,
                    modelId: lastMsg.modelId,
                    agentName: lastMsg.agentName,
                    recordRef: "message · awaiting response"
                )
                continue
            }

            if lastMsg.role == "assistant" && lastMsg.completedMs == nil {
                var partState: AgentRunState = .working
                var partRef = "assistant · streaming"
                var partTimeMs = lastMsg.createdMs

                if hasPartTable {
                    if let latestPart = querySingleLatestPart(db: db, messageId: lastMsg.msgId, sessionId: sessId) {
                        if latestPart.timeMs > 0 { partTimeMs = latestPart.timeMs }
                        if latestPart.status == "error" {
                            partState = .error
                            partRef = "part · error"
                        } else if latestPart.status == "awaiting_approval" || latestPart.type == "permission" {
                            partState = .confirm
                            partRef = "part · confirm"
                        } else if latestPart.type == "reasoning" {
                            partState = .thinking
                            partRef = "part · reasoning"
                        } else if latestPart.type == "tool" || latestPart.type == "patch" || latestPart.type == "step-start" {
                            partState = .working
                            partRef = latestPart.toolName.isEmpty ? "part · \(latestPart.type)" : "tool · \(latestPart.toolName)"
                        } else {
                            partState = .working
                            partRef = "part · \(latestPart.type)"
                        }
                    }
                }

                if (nowMs - max(lastMsg.createdMs, partTimeMs)) <= activeStaleThresholdMs {
                    sessionStates[sessId] = SessionRuntimeInfo(
                        state: partState,
                        stateTimeMs: lastMsg.createdMs > 0 ? lastMsg.createdMs : partTimeMs,
                        lastCompletedDurationSec: durSec,
                        modelId: lastMsg.modelId,
                        agentName: lastMsg.agentName,
                        recordRef: partRef
                    )
                    continue
                }
            }

            let lastTouchMs = lastMsg.completedMs ?? lastMsg.createdMs
            if hasPartTable,
               (nowMs - lastTouchMs) <= 60_000,
               let veryRecentPart = querySingleLatestPart(db: db, messageId: lastMsg.msgId, sessionId: sessId),
               (nowMs - veryRecentPart.timeMs) <= 8_000,
               (veryRecentPart.type == "tool" || veryRecentPart.type == "reasoning" || veryRecentPart.type == "step-start") {
                let st: AgentRunState = (veryRecentPart.type == "reasoning") ? .thinking : .working
                sessionStates[sessId] = SessionRuntimeInfo(
                    state: st,
                    stateTimeMs: veryRecentPart.timeMs,
                    lastCompletedDurationSec: durSec,
                    modelId: lastMsg.modelId,
                    agentName: lastMsg.agentName,
                    recordRef: "part · \(veryRecentPart.type)"
                )
                continue
            }

            sessionStates[sessId] = SessionRuntimeInfo(
                state: .completed,
                stateTimeMs: lastMsg.completedMs ?? lastMsg.createdMs,
                lastCompletedDurationSec: durSec,
                modelId: lastMsg.modelId,
                agentName: lastMsg.agentName,
                recordRef: "message · completed"
            )
        }

        return sessionStates
    }

    private func querySingleLatestPart(
        db: OpaquePointer,
        messageId: String?,
        sessionId: String
    ) -> (type: String, status: String, toolName: String, timeMs: Int64)? {
        let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let sql: String
        let bindValue: String

        if let mid = messageId, !mid.isEmpty {
            sql = """
            SELECT
                COALESCE(json_extract(data, '$.type'), ''),
                COALESCE(json_extract(data, '$.state.status'), ''),
                COALESCE(json_extract(data, '$.tool'), ''),
                COALESCE(time_created, 0)
            FROM part
            WHERE message_id = ?
            ORDER BY id DESC LIMIT 1;
            """
            bindValue = mid
        } else {
            sql = """
            SELECT
                COALESCE(json_extract(data, '$.type'), ''),
                COALESCE(json_extract(data, '$.state.status'), ''),
                COALESCE(json_extract(data, '$.tool'), ''),
                COALESCE(time_created, 0)
            FROM part
            WHERE session_id = ?
            ORDER BY id DESC LIMIT 1;
            """
            bindValue = sessionId
        }

        var stmt: OpaquePointer?
        var out: (String, String, String, Int64)?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            _ = bindValue.withCString { cStr in
                sqlite3_bind_text(stmt, 1, cStr, -1, sqliteTransient)
            }
            if sqlite3_step(stmt) == SQLITE_ROW {
                let pType = colString(stmt, 0) ?? ""
                let pStatus = colString(stmt, 1) ?? ""
                let pTool = colString(stmt, 2) ?? ""
                let pTime = normalizeToMs(sqlite3_column_int64(stmt, 3))
                out = (pType, pStatus, pTool, pTime)
            }
            sqlite3_finalize(stmt)
        }
        return out
    }

    private func buildEmptyHourlySeries(todayStartDate: Date, currentHour: Int) -> [TodayHourlyPoint] {
        return (0..<24).map { hr in
            let hourDate = todayStartDate.addingTimeInterval(Double(hr) * 3600.0 + 60.0)
            let isPeak = (DeepSeekPricingEngine.priceWindow(at: hourDate) == .peak)
            return TodayHourlyPoint(
                hour: hr,
                hourLabel: String(format: "%02d", hr),
                requestCount: 0,
                costCny: 0.0,
                cacheHitPercent: 0.0,
                isPeakHour: isPeak,
                isCurrentHour: hr == currentHour
            )
        }
    }

    private func normalizeToMs(_ raw: Int64) -> Int64 {
        guard raw > 0 else { return 0 }
        return raw < 100_000_000_000 ? raw * 1000 : raw
    }

    private func tableColumns(db: OpaquePointer, table: String) -> Set<String> {
        var cols = Set<String>()
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &stmt, nil) == SQLITE_OK, let stmt {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = colString(stmt, 1) {
                    cols.insert(name)
                }
            }
            sqlite3_finalize(stmt)
        }
        return cols
    }

    private func tableExists(db: OpaquePointer, name: String) -> Bool {
        var exists = false
        var stmt: OpaquePointer?
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;"
        let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            _ = name.withCString { cStr in
                sqlite3_bind_text(stmt, 1, cStr, -1, sqliteTransient)
            }
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
