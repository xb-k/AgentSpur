import Foundation
import SQLite3

struct OpenCodeDBSnapshot: Equatable {
    let masters: [MasterSessionItem]
    let urgentSubTask: SubTaskItem?
    let topState: AgentRunState
    let topStateEnteredAtMs: Int64
    let todayHourlySeries: [TodayHourlyPoint]
    let billing: BillingTelemetrySummary
    let availableKeyScopes: [KeyScopedTelemetry]
    let effectiveProfiles: [APIKeyProfile]
    let realWindows: [RealTerminalWindow]
    let activeDbFileName: String
    let dbExists: Bool

    /// O(1) (<0.1ms) 按 API-Key 提取预聚合账单、分时趋势与会话列表，切换下拉菜单绝不重扫 opencode.db
    func scoped(for keyId: String) -> KeyScopedTelemetry {
        if keyId == APIKeyProfile.allKeysId {
            return KeyScopedTelemetry(
                keyId: APIKeyProfile.allKeysId,
                title: "全部 Key",
                billing: billing,
                todayHourlySeries: todayHourlySeries,
                masters: masters
            )
        }
        if let hit = availableKeyScopes.first(where: { $0.keyId == keyId }) {
            return hit
        }
        return KeyScopedTelemetry(
            keyId: APIKeyProfile.allKeysId,
            title: "全部 Key",
            billing: billing,
            todayHourlySeries: todayHourlySeries,
            masters: masters
        )
    }
}

final class OpenCodeDBReader {
    let opencodeDirPath: String
    private let localCacheDbPath: String

    // 缓存每个会话/子任务上一次的状态与进入该状态的时间戳，确保状态切换时计时自动从 0s 重置
    private var trackedStates: [String: (state: AgentRunState, enteredAtMs: Int64)] = [:]
    private var syncedCacheMsgIds = Set<String>()
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

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: ("~/Library/Application Support" as NSString).expandingTildeInPath)
        let spurDir = appSupport.appendingPathComponent("AgentSpur", isDirectory: true)
        try? FileManager.default.createDirectory(at: spurDir, withIntermediateDirectories: true)
        self.localCacheDbPath = spurDir.appendingPathComponent("telemetry_cache.sqlite").path
        ensureLocalIndexedCacheSchema()
    }

    /// 在 AgentSpur 自有缓存库建立 (api_key, timestamp) 复合索引（绝不修改只读的 opencode.db）
    private func ensureLocalIndexedCacheSchema() {
        var cacheDb: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(localCacheDbPath, &cacheDb, flags, nil) == SQLITE_OK, let cacheDb else {
            if cacheDb != nil { sqlite3_close(cacheDb) }
            return
        }
        defer { sqlite3_close(cacheDb) }

        let ddl = """
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        CREATE TABLE IF NOT EXISTS usage_logs (
            msg_id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            api_key TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            model_id TEXT NOT NULL,
            hit_tokens INTEGER NOT NULL,
            miss_tokens INTEGER NOT NULL,
            out_tokens INTEGER NOT NULL,
            cost_cny REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_usage_key_time ON usage_logs(api_key, timestamp);
        """
        _ = sqlite3_exec(cacheDb, ddl, nil, nil, nil)
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
        configuredProfiles: [APIKeyProfile],
        realWindows: [RealTerminalWindow],
        onNotificationEvent: ((AgentNotificationEvent) -> Void)?
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
        let emptyHourly = buildEmptyHourlySeries(todayStartDate: todayStartDate, currentHour: currentHour)
        let preDbDiscovered = discoverProfilesFromFilesAndEnv(
            candidateDirectories: [],
            activeProviderHints: []
        )
        let fallbackProfiles = mergeDiscoveredAndManualProfiles(
            discovered: preDbDiscovered,
            manual: configuredProfiles
        )
        let emptyScopes = fallbackProfiles.map {
            KeyScopedTelemetry(
                keyId: $0.id,
                title: $0.displayTitle,
                billing: emptyBilling,
                todayHourlySeries: emptyHourly,
                masters: []
            )
        }

        guard let dbPath = resolveActiveDatabasePath() else {
            return OpenCodeDBSnapshot(
                masters: [],
                urgentSubTask: nil,
                topState: .completed,
                topStateEnteredAtMs: nowMs,
                todayHourlySeries: emptyHourly,
                billing: emptyBilling,
                availableKeyScopes: emptyScopes,
                effectiveProfiles: fallbackProfiles,
                realWindows: realWindows,
                activeDbFileName: "opencode.db",
                dbExists: false
            )
        }

        let activeDbName = (dbPath as NSString).lastPathComponent

        var db: OpaquePointer?
        let roFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(dbPath, &db, roFlags, nil) == SQLITE_OK, let db else {
            if db != nil { sqlite3_close(db) }
            return OpenCodeDBSnapshot(
                masters: [],
                urgentSubTask: nil,
                topState: .completed,
                topStateEnteredAtMs: nowMs,
                todayHourlySeries: emptyHourly,
                billing: emptyBilling,
                availableKeyScopes: emptyScopes,
                effectiveProfiles: fallbackProfiles,
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
                todayHourlySeries: emptyHourly,
                billing: emptyBilling,
                availableKeyScopes: emptyScopes,
                effectiveProfiles: fallbackProfiles,
                realWindows: realWindows,
                activeDbFileName: activeDbName,
                dbExists: true
            )
        }

        let hasMessageTable = tableExists(db: db, name: "message")
        let hasPartTable = tableExists(db: db, name: "part")
        let hasPermissionTable = tableExists(db: db, name: "permission")

        // Step 1: O(log N) 二分定位今日第一条 message 的 rowid，单趟扫描今日全量消息
        let todayBillingScan = scanAllTodayMessagesViaRowIdBinarySearch(
            db: db,
            hasMessageTable: hasMessageTable,
            todayStartMs: todayStartMs,
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

        // Step 3: 批量获取活跃会话元数据
        let rawSessions = fetchSessionMetadata(
            db: db,
            sessionCols: sessionCols,
            sessionIds: Array(candidateSessionIds)
        )

        // Step 3.5: 自动从 opencode.db 内部凭据表 + 同级 auth.json + opencode.json + 会话项目配置只读提取 API-Key 与通道
        var candidateDirs: [String] = []
        for meta in rawSessions.values where !meta.directory.isEmpty {
            if !candidateDirs.contains(meta.directory) {
                candidateDirs.append(meta.directory)
            }
        }
        for projDir in queryProjectWorktrees(db: db) where !projDir.isEmpty {
            if !candidateDirs.contains(projDir) {
                candidateDirs.append(projDir)
            }
        }

        var activeHints = Set(todayBillingScan.sessionProviderHint.values.filter { !$0.isEmpty })
        if hasMessageTable {
            activeHints.formUnion(queryRecentMessageProviderHints(db: db, limit: 360))
        }

        let autoDiscovered = discoverOpenCodeProfiles(
            db: db,
            activeDbName: activeDbName,
            candidateDirectories: Array(candidateDirs.prefix(12)),
            activeProviderHints: activeHints
        )
        let effectiveProfiles = mergeDiscoveredAndManualProfiles(
            discovered: autoDiscovered,
            manual: configuredProfiles
        )

        // Step 4: 为每个会话归属对应的 API-Key 分组（支持按目录/ProviderID/Key指纹自动匹配多 Key）
        var sessionToKeyBucket: [String: (id: String, title: String)] = [:]
        let defaultProfile = effectiveProfiles.first(where: { $0.directoryKeyword.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? effectiveProfiles.first

        func resolveRootDirectoryAndTitle(for sessId: String) -> (dir: String, title: String) {
            guard let m = rawSessions[sessId] else { return ("", "") }
            if let pid = m.parentId, let parent = rawSessions[pid] {
                let effDir = m.directory.isEmpty ? parent.directory : m.directory
                return (effDir, "\(parent.title) \(m.title)")
            }
            return (m.directory, m.title)
        }

        for sId in rawSessions.keys {
            let info = resolveRootDirectoryAndTitle(for: sId)
            let providerHint = todayBillingScan.sessionProviderHint[sId] ?? ""
            let bucket = matchKeyBucket(
                directory: info.dir,
                title: info.title,
                providerHint: providerHint,
                configuredProfiles: effectiveProfiles,
                defaultProfile: defaultProfile
            )
            sessionToKeyBucket[sId] = bucket
        }

        // 将今日新消息增量写入带 idx_usage_key_time 索引的本地缓存库，并在内存一次完成全局 + 多 Key 预聚合
        let aggregated = aggregateGlobalAndPerKeyTelemetry(
            records: todayBillingScan.billedRecords,
            sessionToKeyBucket: sessionToKeyBucket,
            configuredProfiles: effectiveProfiles,
            todayStartDate: todayStartDate,
            currentHour: currentHour
        )
        syncNewRecordsToLocalIndexedCache(
            records: todayBillingScan.billedRecords,
            sessionToKeyBucket: sessionToKeyBucket
        )

        // Step 5: 对尚未被今日消息覆盖到的候选会话补齐最新一条消息
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

        // Step 6: 处理状态流转计时与完成/待确认/报错通知（仅顶层主任务或关键确认触发通知，避免子任务刷屏）
        struct ResolvedSession {
            let meta: RawSessionMeta
            let keyBucketId: String
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
            let isTopLevel = (meta.parentId == nil || rawSessions[meta.parentId ?? ""] == nil)

            let effectiveEnteredAtMs: Int64
            if let prev = trackedStates[id] {
                if prev.state != derivedState {
                    effectiveEnteredAtMs = nowMs
                    trackedStates[id] = (derivedState, nowMs)
                    if hasInitializedBaseline {
                        if isTopLevel && prev.state.isActiveRunning && derivedState == .completed {
                            onNotificationEvent?(AgentNotificationEvent(kind: .completed, taskTitle: meta.title))
                        } else if derivedState == .confirm && prev.state != .confirm {
                            onNotificationEvent?(AgentNotificationEvent(kind: .confirmNeeded, taskTitle: meta.title))
                        } else if isTopLevel && prev.state.isActiveRunning && derivedState == .error {
                            onNotificationEvent?(AgentNotificationEvent(kind: .errorOccurred, taskTitle: meta.title))
                        }
                    }
                } else {
                    effectiveEnteredAtMs = prev.enteredAtMs
                }
            } else {
                effectiveEnteredAtMs = dbTimestamp
                trackedStates[id] = (derivedState, dbTimestamp)
            }

            let sBill = todayBillingScan.perSessionBilling[id]
            let kId = sessionToKeyBucket[id]?.id ?? (defaultProfile?.id ?? "key-default")
            resolvedMap[id] = ResolvedSession(
                meta: meta,
                keyBucketId: kId,
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

        // Step 7: 组装 Master 与 Sub-Agent 树
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
                    roleStr = "@sub"
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
                    apiKeyBucket: item.keyBucketId,
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

            subs.sort { a, b in
                if a.state.isActiveRunning != b.state.isActiveRunning {
                    return a.state.isActiveRunning && !b.state.isActiveRunning
                }
                if a.state.activeFirstRank != b.state.activeFirstRank {
                    return a.state.activeFirstRank > b.state.activeFirstRank
                }
                return a.stateEnteredAtMs > b.stateEnteredAtMs
            }

            var effectiveMasterState = item.state
            var effectiveMasterEnteredMs = item.enteredAtMs
            var bestRank = effectiveMasterState.activeFirstRank
            // 仅当子代理正在活跃运行（思考/工作/待确认）时才向上提升主会话状态；
            // 已结束的历史子代理中断或局部报错不应污染已正常完成的主会话。
            for sub in subs where sub.state.isActiveRunning {
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
                apiKeyBucket: item.keyBucketId,
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

        masters.sort { a, b in
            if a.state.isActiveRunning != b.state.isActiveRunning {
                return a.state.isActiveRunning && !b.state.isActiveRunning
            }
            if a.state.activeFirstRank != b.state.activeFirstRank {
                return a.state.activeFirstRank > b.state.activeFirstRank
            }
            return a.stateEnteredAtMs > b.stateEnteredAtMs
        }

        // 将过滤好的会话绑定进各 Key 预聚合分片，供前端 <0.1ms 无感切换
        let finalizedKeyScopes: [KeyScopedTelemetry] = aggregated.keyScopes.map { scope in
            let scopedMasters = masters.filter { $0.apiKeyBucket == scope.keyId }
            return KeyScopedTelemetry(
                keyId: scope.keyId,
                title: scope.title,
                billing: scope.billing,
                todayHourlySeries: scope.todayHourlySeries,
                masters: scopedMasters
            )
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
                apiKeyBucket: m.apiKeyBucket,
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
        if let activeMaster = masters.first(where: { $0.state.isActiveRunning }) {
            var bestActive = activeMaster
            for m in masters where m.state.isActiveRunning {
                if m.state.activeFirstRank > bestActive.state.activeFirstRank {
                    bestActive = m
                }
            }
            topState = bestActive.state
            topEnteredMs = bestActive.stateEnteredAtMs
        } else if let latestMaster = masters.first,
                  latestMaster.state == .error,
                  (nowMs - latestMaster.stateEnteredAtMs) < 10 * 60 * 1000 {
            topState = .error
            topEnteredMs = latestMaster.stateEnteredAtMs
        }

        return OpenCodeDBSnapshot(
            masters: masters,
            urgentSubTask: urgentSubTask,
            topState: topState,
            topStateEnteredAtMs: topEnteredMs,
            todayHourlySeries: aggregated.globalHourly,
            billing: aggregated.globalBilling,
            availableKeyScopes: finalizedKeyScopes,
            effectiveProfiles: effectiveProfiles,
            realWindows: realWindows,
            activeDbFileName: activeDbName,
            dbExists: true
        )
    }

    // MARK: - API-Key Bucket Matching & Local Indexed Cache Sync

    private func matchKeyBucket(
        directory: String,
        title: String,
        providerHint: String,
        configuredProfiles: [APIKeyProfile],
        defaultProfile: APIKeyProfile?
    ) -> (id: String, title: String) {
        let lowerDir = (directory as NSString).expandingTildeInPath.lowercased()
        let haystack = "\(lowerDir) \(directory.lowercased()) \(title.lowercased()) \(providerHint.lowercased())"

        // 1. 优先匹配配置了工作目录或项目路径关键词的专属 Key
        for profile in configuredProfiles {
            let rawKw = profile.directoryKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawKw.isEmpty else { continue }
            let expandedKw = (rawKw as NSString).expandingTildeInPath.lowercased()
            let plainKw = rawKw.lowercased()
            if (!lowerDir.isEmpty && lowerDir.contains(expandedKw)) || haystack.contains(plainKw) {
                return (profile.id, profile.displayTitle)
            }
        }

        // 2. 按 opencode.db 消息中的 providerID / apiKeyName / keyID 精确关联自动读取或手动配置的 Key
        let trimmedHint = providerHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHint.isEmpty {
            let lowerHint = trimmedHint.lowercased()
            let maskedHint = APIKeyProfile.makeMasked(trimmedHint).lowercased()
            if let matched = configuredProfiles.first(where: { prof in
                (!prof.providerId.isEmpty && prof.providerId.lowercased() == lowerHint)
                    || prof.name.lowercased() == lowerHint
                    || (!prof.maskedKey.isEmpty && (prof.maskedKey.lowercased() == lowerHint || prof.maskedKey.lowercased() == maskedHint))
                    || (!prof.rawApiKey.isEmpty && prof.rawApiKey == trimmedHint)
            }) {
                return (matched.id, matched.displayTitle)
            }

            if lowerHint != "deepseek" {
                let bucketId = "channel:\(lowerHint)"
                return (bucketId, "通道 · \(trimmedHint)")
            }
        }

        // 3. 归入默认主 Key
        if let def = defaultProfile {
            return (def.id, def.displayTitle)
        }
        return ("key-default", "默认主Key")
    }

    private struct BilledMessageRecord {
        let msgId: String
        let sessionId: String
        let createdMs: Int64
        let modelId: String
        let hitTokens: Int64
        let missTokens: Int64
        let cacheWriteTokens: Int64
        let outTokens: Int64
        let reasoningTokens: Int64
        let rawUsd: Double
        let breakdown: DeepSeekPricingEngine.RequestCostBreakdown
    }

    private struct BucketAccumulator {
        var id: String
        var title: String
        var hit: Int64 = 0
        var miss: Int64 = 0
        var cacheWrite: Int64 = 0
        var out: Int64 = 0
        var reasoning: Int64 = 0
        var reqs: Int = 0
        var offPeakReqs: Int = 0
        var spurCny: Double = 0.0
        var peakCostCny: Double = 0.0
        var offPeakCostCny: Double = 0.0
        var hitCostCny: Double = 0.0
        var missCostCny: Double = 0.0
        var outCostCny: Double = 0.0
        var cacheSavedCny: Double = 0.0
        var offPeakSavedCny: Double = 0.0
        var openCodeUsd: Double = 0.0
        var modelFreq: [String: Int] = [:]
        var hourlyReqs = Array(repeating: 0, count: 24)
        var hourlyCosts = Array(repeating: 0.0, count: 24)
        var hourlyHits = Array(repeating: Int64(0), count: 24)
        var hourlyTotalIns = Array(repeating: Int64(0), count: 24)

        mutating func ingest(_ rec: BilledMessageRecord, hour: Int) {
            hit += rec.hitTokens
            miss += rec.missTokens
            cacheWrite += rec.cacheWriteTokens
            out += rec.outTokens
            reasoning += rec.reasoningTokens
            reqs += 1
            if rec.breakdown.isOffPeak {
                offPeakReqs += 1
                offPeakCostCny += rec.breakdown.totalCostCny
            } else {
                peakCostCny += rec.breakdown.totalCostCny
            }
            spurCny += rec.breakdown.totalCostCny
            hitCostCny += rec.breakdown.hitCostCny
            missCostCny += rec.breakdown.missCostCny
            outCostCny += rec.breakdown.outputCostCny
            cacheSavedCny += rec.breakdown.cacheSavedCny
            offPeakSavedCny += rec.breakdown.offPeakSavedCny
            openCodeUsd += rec.rawUsd
            modelFreq[rec.modelId, default: 0] += 1

            let h = max(0, min(23, hour))
            hourlyReqs[h] += 1
            hourlyCosts[h] += rec.breakdown.totalCostCny
            hourlyHits[h] += rec.hitTokens
            hourlyTotalIns[h] += (rec.hitTokens + rec.missTokens)
        }

        func buildBilling(dateLabel: String) -> BillingTelemetrySummary {
            let domModel = modelFreq.max(by: { $0.value < $1.value })?.key ?? "deepseek-flash"
            let tier = DeepSeekPricingEngine.classifyModel(domModel)
            return BillingTelemetrySummary(
                dateLabel: dateLabel,
                dominantModelId: tier.canonicalModelId,
                dominantModelSpec: tier.specSummary,
                inputCacheHitTokens: hit,
                inputCacheMissTokens: miss,
                cacheWriteTokens: cacheWrite,
                outputTokens: out,
                reasoningTokens: reasoning,
                requestCount: reqs,
                offPeakRequestCount: offPeakReqs,
                spurCostCny: spurCny,
                peakCostCny: peakCostCny,
                offPeakCostCny: offPeakCostCny,
                cacheHitCostCny: hitCostCny,
                cacheMissCostCny: missCostCny,
                outputCostCny: outCostCny,
                cacheSavedCny: cacheSavedCny,
                offPeakSavedCny: offPeakSavedCny,
                opencodeRawUsd: openCodeUsd
            )
        }

        func buildHourly(todayStartDate: Date, currentHour: Int) -> [TodayHourlyPoint] {
            return (0..<24).map { hr in
                let totIn = hourlyTotalIns[hr]
                let hitPct = totIn > 0 ? (Double(hourlyHits[hr]) / Double(totIn)) * 100.0 : 0.0
                let hourDate = todayStartDate.addingTimeInterval(Double(hr) * 3600.0 + 60.0)
                let isPeak = (DeepSeekPricingEngine.priceWindow(at: hourDate) == .peak)
                return TodayHourlyPoint(
                    hour: hr,
                    hourLabel: String(format: "%02d", hr),
                    requestCount: hourlyReqs[hr],
                    costCny: hourlyCosts[hr],
                    cacheHitPercent: hitPct,
                    isPeakHour: isPeak,
                    isCurrentHour: hr == currentHour
                )
            }
        }
    }

    private func aggregateGlobalAndPerKeyTelemetry(
        records: [BilledMessageRecord],
        sessionToKeyBucket: [String: (id: String, title: String)],
        configuredProfiles: [APIKeyProfile],
        todayStartDate: Date,
        currentHour: Int
    ) -> (globalBilling: BillingTelemetrySummary, globalHourly: [TodayHourlyPoint], keyScopes: [KeyScopedTelemetry]) {
        let dateLabel = TimeFormatters.todayShortLabel()
        let localCal = Calendar.current

        var globalAcc = BucketAccumulator(id: APIKeyProfile.allKeysId, title: "全部 Key")
        var keyAccMap: [String: BucketAccumulator] = [:]
        var orderedKeyIds: [String] = []

        for p in configuredProfiles {
            keyAccMap[p.id] = BucketAccumulator(id: p.id, title: p.displayTitle)
            orderedKeyIds.append(p.id)
        }

        let fallbackId = configuredProfiles.first?.id ?? "key-default"
        let fallbackTitle = configuredProfiles.first?.displayTitle ?? "默认主Key"

        for rec in records {
            let msgDate = Date(timeIntervalSince1970: Double(rec.createdMs) / 1000.0)
            let hr = localCal.component(.hour, from: msgDate)
            globalAcc.ingest(rec, hour: hr)

            let bucket = sessionToKeyBucket[rec.sessionId] ?? (fallbackId, fallbackTitle)
            if keyAccMap[bucket.id] == nil {
                keyAccMap[bucket.id] = BucketAccumulator(id: bucket.id, title: bucket.title)
                orderedKeyIds.append(bucket.id)
            }
            keyAccMap[bucket.id]?.ingest(rec, hour: hr)
        }

        if orderedKeyIds.isEmpty {
            let defAcc = BucketAccumulator(id: "key-default", title: "默认主Key")
            keyAccMap["key-default"] = defAcc
            orderedKeyIds.append("key-default")
        }

        let scopes: [KeyScopedTelemetry] = orderedKeyIds.compactMap { kId in
            guard let acc = keyAccMap[kId] else { return nil }
            return KeyScopedTelemetry(
                keyId: acc.id,
                title: acc.title,
                billing: acc.buildBilling(dateLabel: dateLabel),
                todayHourlySeries: acc.buildHourly(todayStartDate: todayStartDate, currentHour: currentHour),
                masters: []
            )
        }

        return (
            globalAcc.buildBilling(dateLabel: dateLabel),
            globalAcc.buildHourly(todayStartDate: todayStartDate, currentHour: currentHour),
            scopes
        )
    }

    private func syncNewRecordsToLocalIndexedCache(
        records: [BilledMessageRecord],
        sessionToKeyBucket: [String: (id: String, title: String)]
    ) {
        let unsynced = records.filter { !$0.msgId.isEmpty && !syncedCacheMsgIds.contains($0.msgId) }
        guard !unsynced.isEmpty else { return }

        var cacheDb: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(localCacheDbPath, &cacheDb, flags, nil) == SQLITE_OK, let cacheDb else {
            if cacheDb != nil { sqlite3_close(cacheDb) }
            return
        }
        defer { sqlite3_close(cacheDb) }

        _ = sqlite3_exec(cacheDb, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil)
        let sql = """
        INSERT OR REPLACE INTO usage_logs
        (msg_id, session_id, api_key, timestamp, model_id, hit_tokens, miss_tokens, out_tokens, cost_cny)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(cacheDb, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            for rec in unsynced {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                let keyId = sessionToKeyBucket[rec.sessionId]?.id ?? "key-default"
                _ = rec.msgId.withCString { sqlite3_bind_text(stmt, 1, $0, -1, sqliteTransient) }
                _ = rec.sessionId.withCString { sqlite3_bind_text(stmt, 2, $0, -1, sqliteTransient) }
                _ = keyId.withCString { sqlite3_bind_text(stmt, 3, $0, -1, sqliteTransient) }
                sqlite3_bind_int64(stmt, 4, rec.createdMs)
                _ = rec.modelId.withCString { sqlite3_bind_text(stmt, 5, $0, -1, sqliteTransient) }
                sqlite3_bind_int64(stmt, 6, rec.hitTokens)
                sqlite3_bind_int64(stmt, 7, rec.missTokens)
                sqlite3_bind_int64(stmt, 8, rec.outTokens)
                sqlite3_bind_double(stmt, 9, rec.breakdown.totalCostCny)
                _ = sqlite3_step(stmt)
                syncedCacheMsgIds.insert(rec.msgId)
            }
            sqlite3_finalize(stmt)
        }
        _ = sqlite3_exec(cacheDb, "COMMIT;", nil, nil, nil)
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
        let billedRecords: [BilledMessageRecord]
        let perSessionBilling: [String: SessionBillingAcc]
        let sessionProviderHint: [String: String]
        let touchedSessionIds: Set<String>
        let latestMsgPerSession: [String: LatestMsgRecord]
        let lastCompletedDurPerSession: [String: Int64]
    }

    /// 用 SQLite B-Tree 主键 rowid 二分查找定位今日 00:00 起始行（耗时 <0.1ms），零扫全表
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

        return max(1, ans - 800)
    }

    private func scanAllTodayMessagesViaRowIdBinarySearch(
        db: OpaquePointer,
        hasMessageTable: Bool,
        todayStartMs: Int64,
        usdToCnyRate: Double
    ) -> TodayMessageScanResult {
        guard hasMessageTable else {
            return TodayMessageScanResult(
                billedRecords: [],
                perSessionBilling: [:],
                sessionProviderHint: [:],
                touchedSessionIds: [],
                latestMsgPerSession: [:],
                lastCompletedDurPerSession: [:]
            )
        }

        let startRowId = findFirstMessageRowIdOnOrAfter(db: db, targetMs: todayStartMs)

        var billedRecords: [BilledMessageRecord] = []
        var perSessionBilling: [String: SessionBillingAcc] = [:]
        var sessionProviderHint: [String: String] = [:]
        var touchedSessionIds = Set<String>()
        var latestMsgPerSession: [String: LatestMsgRecord] = [:]
        var lastCompletedDurPerSession: [String: Int64] = [:]

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
            COALESCE(json_extract(data, '$.cost'), 0.0) AS raw_usd,
            COALESCE(
                json_extract(data, '$.apiKeyName'),
                json_extract(data, '$.keyID'),
                json_extract(data, '$.providerID'),
                json_extract(data, '$.model.providerID'),
                ''
            ) AS key_hint
        FROM message
        WHERE rowid >= ?
        ORDER BY rowid ASC;
        """

        var stmt: OpaquePointer?
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
                let keyHint = colString(stmt, 15) ?? ""

                if !keyHint.isEmpty {
                    sessionProviderHint[sessId] = keyHint
                }

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

                billedRecords.append(BilledMessageRecord(
                    msgId: msgId,
                    sessionId: sessId,
                    createdMs: createdMs,
                    modelId: modelId,
                    hitTokens: hit,
                    missTokens: miss,
                    cacheWriteTokens: cacheWrite,
                    outTokens: billedOut,
                    reasoningTokens: min(billedOut, rawReas),
                    rawUsd: rawUsd,
                    breakdown: bd
                ))

                var acc = perSessionBilling[sessId] ?? SessionBillingAcc()
                acc.hitTokens += hit
                acc.missTokens += miss
                acc.outTokens += billedOut
                acc.requests += 1
                acc.costCny += bd.totalCostCny
                acc.rawUsd += rawUsd
                acc.cacheSavedCny += bd.cacheSavedCny
                perSessionBilling[sessId] = acc
            }
            sqlite3_finalize(stmt)
        }

        return TodayMessageScanResult(
            billedRecords: billedRecords,
            perSessionBilling: perSessionBilling,
            sessionProviderHint: sessionProviderHint,
            touchedSessionIds: touchedSessionIds,
            latestMsgPerSession: latestMsgPerSession,
            lastCompletedDurPerSession: lastCompletedDurPerSession
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

    // MARK: - Read-Only Automatic API-Key & Provider Discovery (opencode.db + auth.json + opencode.json + .env)

    private func queryProjectWorktrees(db: OpaquePointer) -> [String] {
        guard tableExists(db: db, name: "project") else { return [] }
        let cols = tableColumns(db: db, table: "project")
        guard cols.contains("worktree") else { return [] }
        var dirs: [String] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT DISTINCT worktree FROM project WHERE worktree IS NOT NULL AND worktree != '' LIMIT 16;", -1, &stmt, nil) == SQLITE_OK, let stmt {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let d = colString(stmt, 0), !d.isEmpty {
                    dirs.append(d)
                }
            }
            sqlite3_finalize(stmt)
        }
        return dirs
    }

    private func queryRecentMessageProviderHints(db: OpaquePointer, limit: Int) -> Set<String> {
        var hints = Set<String>()
        let sql = """
        SELECT DISTINCT hint FROM (
            SELECT COALESCE(
                NULLIF(json_extract(data, '$.apiKeyName'), ''),
                NULLIF(json_extract(data, '$.keyID'), ''),
                NULLIF(json_extract(data, '$.providerID'), ''),
                NULLIF(json_extract(data, '$.model.providerID'), ''),
                ''
            ) AS hint
            FROM message
            ORDER BY rowid DESC
            LIMIT \(max(50, limit))
        ) WHERE hint != '';
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let h = colString(stmt, 0), !h.isEmpty {
                    hints.insert(h)
                }
            }
            sqlite3_finalize(stmt)
        }
        return hints
    }

    private func discoverOpenCodeProfiles(
        db: OpaquePointer,
        activeDbName: String,
        candidateDirectories: [String],
        activeProviderHints: Set<String>
    ) -> [APIKeyProfile] {
        var found: [APIKeyProfile] = []

        func appendCandidate(
            idSeed: String,
            name: String,
            rawKey: String,
            directoryKeyword: String = "",
            providerId: String = "",
            source: String
        ) {
            let cleanKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanProvider = providerId.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let masked = cleanKey.isEmpty ? "" : APIKeyProfile.makeMasked(cleanKey)

            if !cleanKey.isEmpty {
                if let existingIdx = found.firstIndex(where: { $0.rawApiKey == cleanKey }) {
                    if found[existingIdx].providerId.isEmpty && !cleanProvider.isEmpty {
                        found[existingIdx].providerId = cleanProvider
                    }
                    if found[existingIdx].directoryKeyword.isEmpty && !directoryKeyword.isEmpty {
                        found[existingIdx].directoryKeyword = directoryKeyword
                    }
                    return
                }
            } else if !cleanProvider.isEmpty {
                if found.contains(where: { $0.providerId.lowercased() == cleanProvider.lowercased() }) {
                    return
                }
            } else {
                return
            }

            let safeSeed = idSeed
                .lowercased()
                .replacingOccurrences(of: "[^a-z0-9_-]", with: "-", options: .regularExpression)
            let finalId = "auto-\(safeSeed.isEmpty ? UUID().uuidString.prefix(6) : Substring(safeSeed.prefix(28)))"
            let finalName = cleanName.isEmpty ? friendlyProviderDisplayName(cleanProvider) : cleanName

            found.append(APIKeyProfile(
                id: finalId,
                name: finalName,
                rawApiKey: cleanKey,
                maskedKey: masked,
                directoryKeyword: directoryKeyword,
                providerId: cleanProvider,
                autoSource: source
            ))
        }

        // 1. 扫描 opencode.db 内部凭据/账号/Provider 配置表（如 credential / account / control_account / auth / provider）
        let skipTables: Set<String> = ["session", "message", "part", "todo", "permission", "project", "workspace"]
        var candidateTables: [String] = []
        var tblStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table';", -1, &tblStmt, nil) == SQLITE_OK, let tblStmt {
            while sqlite3_step(tblStmt) == SQLITE_ROW {
                if let tName = colString(tblStmt, 0) {
                    let lower = tName.lowercased()
                    guard !lower.hasPrefix("sqlite_"), !skipTables.contains(lower) else { continue }
                    if lower.contains("cred") || lower.contains("auth") || lower.contains("account")
                        || lower.contains("provider") || lower.contains("key") || lower.contains("config") || lower.contains("setting") {
                        candidateTables.append(tName)
                    }
                }
            }
            sqlite3_finalize(tblStmt)
        }

        for table in candidateTables {
            let safeTable = table.replacingOccurrences(of: "\"", with: "\"\"")
            var rowStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT * FROM \"\(safeTable)\" LIMIT 100;", -1, &rowStmt, nil) == SQLITE_OK,
                  let rowStmt else { continue }
            let colCount = sqlite3_column_count(rowStmt)
            var rowIdx = 0
            while sqlite3_step(rowStmt) == SQLITE_ROW {
                rowIdx += 1
                var rowProvider = ""
                var rowDisplayName = ""
                var extractedKeys: [String] = []

                for c in 0..<colCount {
                    let cName = sqlite3_column_name(rowStmt, c).map { String(cString: $0).lowercased() } ?? ""
                    guard let val = colString(rowStmt, c), !val.isEmpty else { continue }

                    if (cName == "provider" || cName == "provider_id" || cName == "providerid" || cName == "id") && rowProvider.isEmpty && !val.hasPrefix("sk-") {
                        rowProvider = val
                    } else if (cName == "name" || cName == "label" || cName == "title") && rowDisplayName.isEmpty && !val.hasPrefix("sk-") {
                        rowDisplayName = val
                    }

                    let matches = extractSkKeys(from: val)
                    for k in matches where !extractedKeys.contains(k) {
                        extractedKeys.append(k)
                    }
                }

                for (kIdx, rawKey) in extractedKeys.enumerated() {
                    let isDeepSeekRelated = rowProvider.lowercased().contains("deepseek")
                        || rowDisplayName.lowercased().contains("deepseek")
                        || activeProviderHints.contains(where: { $0.lowercased() == rowProvider.lowercased() })
                        || activeProviderHints.isEmpty
                    guard isDeepSeekRelated || rawKey.hasPrefix("sk-") else { continue }
                    let label = !rowDisplayName.isEmpty
                        ? rowDisplayName
                        : (!rowProvider.isEmpty ? friendlyProviderDisplayName(rowProvider) : "数据库提取Key")
                    appendCandidate(
                        idSeed: "db-\(table)-\(rowProvider)-\(rowIdx)-\(kIdx)",
                        name: label,
                        rawKey: rawKey,
                        providerId: rowProvider.isEmpty ? "deepseek" : rowProvider,
                        source: activeDbName
                    )
                }
            }
            sqlite3_finalize(rowStmt)
        }

        // 2. 若 opencode.db 的 message.data 中直接带有 sk-... 或自定义 key 标签，直接提取
        for hint in activeProviderHints {
            let directKeys = extractSkKeys(from: hint)
            for k in directKeys {
                appendCandidate(
                    idSeed: "msg-\(k.suffix(4))",
                    name: "DB消息Key",
                    rawKey: k,
                    providerId: hint,
                    source: activeDbName
                )
            }
        }

        // 3. 合并同目录 auth.json / ~/.config/opencode/opencode.json / 项目配置 / 环境变量中的 Key
        let fileProfiles = discoverProfilesFromFilesAndEnv(
            candidateDirectories: candidateDirectories,
            activeProviderHints: activeProviderHints
        )
        for fp in fileProfiles {
            appendCandidate(
                idSeed: fp.id.replacingOccurrences(of: "auto-", with: ""),
                name: fp.name,
                rawKey: fp.rawApiKey,
                directoryKeyword: fp.directoryKeyword,
                providerId: fp.providerId,
                source: fp.autoSource ?? "opencode"
            )
        }

        // 4. 若 opencode.db 存在活跃的 providerID / key 通道但本地未存明文 sk-，依然自动生成只读通道项供一键筛选账单
        let sortedHints = activeProviderHints.sorted()
        for hint in sortedHints {
            let lower = hint.lowercased()
            let alreadyCovered = found.contains { prof in
                prof.providerId.lowercased() == lower || prof.name.lowercased() == lower
            }
            if !alreadyCovered && (lower.contains("deepseek") || sortedHints.count > 1) {
                appendCandidate(
                    idSeed: "ch-\(lower)",
                    name: friendlyProviderDisplayName(hint),
                    rawKey: "",
                    providerId: hint,
                    source: activeDbName
                )
            }
        }

        return found
    }

    private func discoverProfilesFromFilesAndEnv(
        candidateDirectories: [String],
        activeProviderHints: Set<String>
    ) -> [APIKeyProfile] {
        let fm = FileManager.default
        let envMap = loadLocalEnvVariables(projectDirectories: candidateDirectories)
        var results: [APIKeyProfile] = []

        func recordKey(
            seed: String,
            name: String,
            rawKey: String,
            directoryKeyword: String = "",
            providerId: String,
            source: String
        ) {
            let resolved = resolveEnvPlaceholder(rawKey, envMap: envMap)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard resolved.count >= 8 else { return }

            let lowerProv = providerId.lowercased()
            let lowerName = name.lowercased()
            let isRelevant = lowerProv.contains("deepseek")
                || lowerName.contains("deepseek")
                || activeProviderHints.contains(where: { $0.lowercased() == lowerProv })
                || (activeProviderHints.isEmpty && resolved.hasPrefix("sk-"))
            guard isRelevant else { return }

            if let idx = results.firstIndex(where: { $0.rawApiKey == resolved }) {
                if results[idx].directoryKeyword.isEmpty && !directoryKeyword.isEmpty {
                    results[idx].directoryKeyword = directoryKeyword
                }
                if (results[idx].name == "DeepSeek 官方" || results[idx].name.hasPrefix("DeepSeek")) && !name.isEmpty && name != providerId {
                    results[idx].name = name
                }
                return
            }

            let cleanSeed = seed
                .lowercased()
                .replacingOccurrences(of: "[^a-z0-9_-]", with: "-", options: .regularExpression)
            results.append(APIKeyProfile(
                id: "auto-\(cleanSeed.prefix(28))",
                name: name.isEmpty ? friendlyProviderDisplayName(providerId) : name,
                rawApiKey: resolved,
                maskedKey: APIKeyProfile.makeMasked(resolved),
                directoryKeyword: directoryKeyword,
                providerId: providerId.isEmpty ? "deepseek" : providerId,
                autoSource: source
            ))
        }

        // A. 扫描 ~/.local/share/opencode/auth.json (与 opencode.db 同目录的官方凭据文件)
        let authJsonCandidates = [
            (opencodeDirPath as NSString).appendingPathComponent("auth.json"),
            ("~/.local/share/opencode/auth.json" as NSString).expandingTildeInPath,
            ("~/.config/opencode/auth.json" as NSString).expandingTildeInPath
        ]
        var visitedPaths = Set<String>()
        for path in authJsonCandidates {
            let stdPath = (path as NSString).standardizingPath
            guard !visitedPaths.contains(stdPath), fm.fileExists(atPath: stdPath) else { continue }
            visitedPaths.insert(stdPath)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: stdPath)),
                  data.count <= 512_000,
                  let rawText = String(data: data, encoding: .utf8) else { continue }

            let cleaned = stripJSONCommentsAndTrailingCommas(rawText)
            if let cleanData = cleaned.data(using: .utf8),
               let root = try? JSONSerialization.jsonObject(with: cleanData) as? [String: Any] {
                for (provId, val) in root {
                    if let dict = val as? [String: Any] {
                        let keyStr = (dict["key"] as? String)
                            ?? (dict["apiKey"] as? String)
                            ?? (dict["api_key"] as? String)
                            ?? (dict["token"] as? String)
                            ?? (dict["access"] as? String)
                            ?? ""
                        let dispName = (dict["name"] as? String) ?? friendlyProviderDisplayName(provId)
                        if !keyStr.isEmpty {
                            recordKey(
                                seed: "auth-\(provId)",
                                name: dispName,
                                rawKey: keyStr,
                                providerId: provId,
                                source: "auth.json"
                            )
                        }
                    } else if let directStr = val as? String, directStr.hasPrefix("sk-") {
                        recordKey(
                            seed: "auth-\(provId)",
                            name: friendlyProviderDisplayName(provId),
                            rawKey: directStr,
                            providerId: provId,
                            source: "auth.json"
                        )
                    }
                }
            }
        }

        // B. 扫描全局及项目级 opencode.json / opencode.jsonc / config.json
        var configEntries: [(path: String, dirScope: String, sourceLabel: String)] = []
        let xdgConfig = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            .map { ($0 as NSString).expandingTildeInPath }
            ?? ("~/.config" as NSString).expandingTildeInPath
        let globalConfigDir = (xdgConfig as NSString).appendingPathComponent("opencode")
        for fileName in ["opencode.json", "opencode.jsonc", "config.json"] {
            configEntries.append(((globalConfigDir as NSString).appendingPathComponent(fileName), "", fileName))
            let homeDotDir = ("~/.opencode" as NSString).expandingTildeInPath
            configEntries.append(((homeDotDir as NSString).appendingPathComponent(fileName), "", fileName))
        }
        for projDir in candidateDirectories {
            let expandedProj = (projDir as NSString).expandingTildeInPath
            configEntries.append(((expandedProj as NSString).appendingPathComponent("opencode.json"), projDir, "项目 opencode.json"))
            configEntries.append(((expandedProj as NSString).appendingPathComponent("opencode.jsonc"), projDir, "项目 opencode.jsonc"))
            configEntries.append(((expandedProj as NSString).appendingPathComponent(".opencode/opencode.json"), projDir, "项目 .opencode"))
        }

        for entry in configEntries {
            let stdPath = (entry.path as NSString).standardizingPath
            guard !visitedPaths.contains(stdPath), fm.fileExists(atPath: stdPath) else { continue }
            visitedPaths.insert(stdPath)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: stdPath)),
                  data.count <= 512_000,
                  let rawText = String(data: data, encoding: .utf8) else { continue }

            let cleaned = stripJSONCommentsAndTrailingCommas(rawText)
            guard let cleanData = cleaned.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: cleanData) as? [String: Any] else { continue }

            let providersDict = (root["provider"] as? [String: Any])
                ?? (root["providers"] as? [String: Any])
                ?? [:]
            for (provId, rawProv) in providersDict {
                guard let provDict = rawProv as? [String: Any] else { continue }
                let dispName = (provDict["name"] as? String) ?? friendlyProviderDisplayName(provId)
                let opts = (provDict["options"] as? [String: Any])
                    ?? (provDict["settings"] as? [String: Any])
                    ?? [:]
                let apiKey = (opts["apiKey"] as? String)
                    ?? (opts["api_key"] as? String)
                    ?? (provDict["apiKey"] as? String)
                    ?? (provDict["key"] as? String)
                    ?? ""
                let baseURL = (opts["baseURL"] as? String) ?? (opts["baseUrl"] as? String) ?? ""
                let effectiveProvId = baseURL.lowercased().contains("deepseek") && !provId.lowercased().contains("deepseek")
                    ? "\(provId)"
                    : provId
                if !apiKey.isEmpty {
                    let finalName = baseURL.lowercased().contains("deepseek") && !dispName.lowercased().contains("deepseek") && dispName == provId
                        ? "DeepSeek · \(dispName)"
                        : dispName
                    recordKey(
                        seed: "cfg-\(provId)-\(entry.dirScope.suffix(10))",
                        name: finalName,
                        rawKey: apiKey,
                        directoryKeyword: entry.dirScope,
                        providerId: effectiveProvId,
                        source: entry.sourceLabel
                    )
                }
            }
        }

        // C. 补充环境变量或项目 .env 中的 DEEPSEEK_API_KEY（支持多 Key 环境变量如 DEEPSEEK_API_KEY_2）
        for (envKey, envVal) in envMap.sorted(by: { $0.key < $1.key }) {
            let upper = envKey.uppercased()
            guard upper.contains("DEEPSEEK") && upper.contains("KEY") else { continue }
            let trimmed = envVal.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 8 else { continue }
            let label = upper == "DEEPSEEK_API_KEY" ? "DeepSeek 环境变量Key" : envKey
            recordKey(
                seed: "env-\(envKey)",
                name: label,
                rawKey: trimmed,
                providerId: "deepseek",
                source: "环境变量"
            )
        }

        return results
    }

    private func mergeDiscoveredAndManualProfiles(
        discovered: [APIKeyProfile],
        manual: [APIKeyProfile]
    ) -> [APIKeyProfile] {
        var merged: [APIKeyProfile] = manual.filter { prof in
            if !discovered.isEmpty,
               prof.id == "key-default",
               prof.rawApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               prof.directoryKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               prof.name == "默认主Key" {
                return false
            }
            return true
        }

        for disc in discovered {
            if let idx = merged.firstIndex(where: { existing in
                existing.id == disc.id
                    || (!existing.rawApiKey.isEmpty && !disc.rawApiKey.isEmpty && existing.rawApiKey == disc.rawApiKey)
                    || (existing.rawApiKey.isEmpty && !disc.rawApiKey.isEmpty && existing.name.lowercased() == disc.name.lowercased())
            }) {
                if merged[idx].rawApiKey.isEmpty && !disc.rawApiKey.isEmpty {
                    merged[idx].rawApiKey = disc.rawApiKey
                    merged[idx].maskedKey = disc.maskedKey
                }
                if merged[idx].providerId.isEmpty && !disc.providerId.isEmpty {
                    merged[idx].providerId = disc.providerId
                }
                if merged[idx].directoryKeyword.isEmpty && !disc.directoryKeyword.isEmpty {
                    merged[idx].directoryKeyword = disc.directoryKeyword
                }
                if merged[idx].autoSource == nil {
                    merged[idx].autoSource = disc.autoSource
                }
            } else {
                merged.append(disc)
            }
        }

        if merged.isEmpty {
            merged.append(APIKeyProfile(
                id: "key-default",
                name: "默认主Key",
                rawApiKey: "",
                maskedKey: "",
                directoryKeyword: ""
            ))
        }

        return merged
    }

    private func friendlyProviderDisplayName(_ providerId: String) -> String {
        let lower = providerId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty || lower == "deepseek" {
            return "DeepSeek 官方"
        }
        if lower.hasPrefix("deepseek-") || lower.hasPrefix("deepseek_") {
            let suffix = String(providerId.dropFirst("deepseek-".count))
            return "DeepSeek · \(suffix)"
        }
        return providerId
    }

    private func extractSkKeys(from text: String) -> [String] {
        guard text.contains("sk-") else { return [] }
        guard let regex = try? NSRegularExpression(pattern: "sk-[A-Za-z0-9_-]{12,128}") else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)
        var out: [String] = []
        for m in matches {
            if let r = Range(m.range, in: text) {
                let key = String(text[r])
                if !out.contains(key) {
                    out.append(key)
                }
            }
        }
        return out
    }

    private func loadLocalEnvVariables(projectDirectories: [String]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let fm = FileManager.default
        var candidateFiles: [String] = [
            (opencodeDirPath as NSString).appendingPathComponent(".env"),
            ("~/.config/opencode/.env" as NSString).expandingTildeInPath,
            ("~/.zshenv" as NSString).expandingTildeInPath,
            ("~/.zshrc" as NSString).expandingTildeInPath,
            ("~/.zprofile" as NSString).expandingTildeInPath,
            ("~/.bash_profile" as NSString).expandingTildeInPath
        ]
        for dir in projectDirectories {
            let expanded = (dir as NSString).expandingTildeInPath
            candidateFiles.append((expanded as NSString).appendingPathComponent(".env"))
        }

        var seen = Set<String>()
        for path in candidateFiles {
            let std = (path as NSString).standardizingPath
            guard !seen.contains(std), fm.fileExists(atPath: std) else { continue }
            seen.insert(std)
            guard let attrs = try? fm.attributesOfItem(atPath: std),
                  let fileSize = attrs[.size] as? NSNumber,
                  fileSize.intValue <= 256_000,
                  let content = try? String(contentsOfFile: std, encoding: .utf8) else { continue }

            for rawLine in content.components(separatedBy: .newlines) {
                var line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#") else { continue }
                if line.hasPrefix("export ") {
                    line = String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
                }
                guard let eqIdx = line.firstIndex(of: "=") else { continue }
                let k = String(line[..<eqIdx]).trimmingCharacters(in: .whitespaces)
                guard !k.isEmpty, env[k] == nil else { continue }
                var v = String(line[line.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
                if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")), v.count >= 2 {
                    v = String(v.dropFirst().dropLast())
                }
                if !v.isEmpty {
                    env[k] = v
                }
            }
        }
        return env
    }

    private func resolveEnvPlaceholder(_ raw: String, envMap: [String: String]) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{env:"), trimmed.hasSuffix("}"), trimmed.count > 6 {
            let varName = String(trimmed.dropFirst(5).dropLast()).trimmingCharacters(in: .whitespaces)
            return envMap[varName] ?? ""
        }
        if trimmed.hasPrefix("${"), trimmed.hasSuffix("}"), trimmed.count > 3 {
            let varName = String(trimmed.dropFirst(2).dropLast()).trimmingCharacters(in: .whitespaces)
            return envMap[varName] ?? ""
        }
        if trimmed.hasPrefix("$"), !trimmed.contains(" "), trimmed.count > 2 {
            let varName = String(trimmed.dropFirst())
            return envMap[varName] ?? trimmed
        }
        return trimmed
    }

    /// 安全剥离 JSONC 中的 // 单行注释、/* */ 块注释以及尾随逗号，绝不破坏字符串字面量内的 https://
    private func stripJSONCommentsAndTrailingCommas(_ raw: String) -> String {
        let chars = Array(raw)
        let n = chars.count
        var pass1: [Character] = []
        pass1.reserveCapacity(n)

        var i = 0
        var inString = false
        var escaped = false

        while i < n {
            let ch = chars[i]
            if inString {
                pass1.append(ch)
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                i += 1
            } else {
                if ch == "\"" {
                    inString = true
                    pass1.append(ch)
                    i += 1
                } else if ch == "/", i + 1 < n, chars[i + 1] == "/" {
                    i += 2
                    while i < n && chars[i] != "\n" {
                        i += 1
                    }
                } else if ch == "/", i + 1 < n, chars[i + 1] == "*" {
                    i += 2
                    while i + 1 < n && !(chars[i] == "*" && chars[i + 1] == "/") {
                        i += 1
                    }
                    i += 2
                } else {
                    pass1.append(ch)
                    i += 1
                }
            }
        }

        var pass2: [Character] = []
        pass2.reserveCapacity(pass1.count)
        let m = pass1.count
        var j = 0
        inString = false
        escaped = false

        while j < m {
            let ch = pass1[j]
            if inString {
                pass2.append(ch)
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                j += 1
            } else {
                if ch == "\"" {
                    inString = true
                    pass2.append(ch)
                    j += 1
                } else if ch == "," {
                    var k = j + 1
                    while k < m && (pass1[k] == " " || pass1[k] == "\t" || pass1[k] == "\r" || pass1[k] == "\n") {
                        k += 1
                    }
                    if k < m && (pass1[k] == "}" || pass1[k] == "]") {
                        j += 1 // 跳过尾随逗号
                    } else {
                        pass2.append(ch)
                        j += 1
                    }
                } else {
                    pass2.append(ch)
                    j += 1
                }
            }
        }

        return String(pass2)
    }
}
