import Foundation

// MARK: - DeepSeek Official Tiered Pricing, UTC+8 Window, Online FX & CSV Engine

enum DeepSeekPricingEngine {
    /// 单 Token 人民币单价（严格对齐官方规格表与 amount.csv 的 price 字段）
    struct TokenUnitRatesCNY {
        let cacheHitPerToken: Double   // input_cache_hit_tokens
        let cacheMissPerToken: Double  // input_cache_miss_tokens
        let outputPerToken: Double     // output_tokens (含 reasoning)

        var hitPerMillion: Double { cacheHitPerToken * 1_000_000.0 }
        var missPerMillion: Double { cacheMissPerToken * 1_000_000.0 }
        var outPerMillion: Double { outputPerToken * 1_000_000.0 }

        var perMillionSummary: String {
            return String(format: "命中 ¥%.2f · 未命中 ¥%.2f · 输出 ¥%.2f /M", hitPerMillion, missPerMillion, outPerMillion)
        }
    }

    struct RequestCostBreakdown {
        let totalCostCny: Double
        let hitCostCny: Double
        let missCostCny: Double
        let outputCostCny: Double
        let cacheSavedCny: Double
        let offPeakSavedCny: Double
        let isOffPeak: Bool
    }

    // 北京时间固定时区 (UTC+8)，不随本机系统时区漂移
    private static let beijingTimeZone = TimeZone(secondsFromGMT: 8 * 3600)!

    private static var beijingCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = beijingTimeZone
        return cal
    }()

    // 中国法定节假日 (UTC+8 全天享受 Off-Peak 5 折优惠)
    private static let chinaStatutoryHolidays: Set<String> = [
        // 2025 法定节假日
        "2025-01-01",
        "2025-01-28", "2025-01-29", "2025-01-30", "2025-01-31", "2025-02-01", "2025-02-02", "2025-02-03", "2025-02-04",
        "2025-04-04", "2025-04-05", "2025-04-06",
        "2025-05-01", "2025-05-02", "2025-05-03", "2025-05-04", "2025-05-05",
        "2025-05-31", "2025-06-01", "2025-06-02",
        "2025-10-01", "2025-10-02", "2025-10-03", "2025-10-04", "2025-10-05", "2025-10-06", "2025-10-07", "2025-10-08",
        // 2026 法定节假日
        "2026-01-01", "2026-01-02", "2026-01-03",
        "2026-02-15", "2026-02-16", "2026-02-17", "2026-02-18", "2026-02-19", "2026-02-20", "2026-02-21", "2026-02-22", "2026-02-23",
        "2026-04-04", "2026-04-05", "2026-04-06",
        "2026-05-01", "2026-05-02", "2026-05-03", "2026-05-04", "2026-05-05",
        "2026-06-19", "2026-06-20", "2026-06-21",
        "2026-09-25", "2026-09-26", "2026-09-27",
        "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06", "2026-10-07",
        // 2027 常规覆盖
        "2027-01-01", "2027-02-05", "2027-02-06", "2027-02-07", "2027-02-08", "2027-02-09", "2027-02-10", "2027-02-11",
        "2027-05-01", "2027-05-02", "2027-05-03",
        "2027-10-01", "2027-10-02", "2027-10-03", "2027-10-04", "2027-10-05", "2027-10-06", "2027-10-07"
    ]

    // MARK: - Model Normalization (Supports DeepSeek-V4.1-Flash, deepseek-flash, deepseek-v4-pro, etc.)

    static func classifyModel(_ rawModelId: String) -> DeepSeekModelTier {
        let lower = rawModelId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let modelPart = lower.split(separator: "/").last.map(String.init) ?? lower

        if modelPart.contains("flash")
            || modelPart.contains("deepseek-chat") {
            return .flash
        }

        if modelPart.contains("v4-pro")
            || modelPart.contains("deepseek-pro")
            || modelPart == "deepseek-reasoner" {
            return .v4Pro
        }

        if lower.contains("deepseek") {
            return .flash
        }

        return .other(rawModelId)
    }

    // MARK: - Beijing Time (UTC+8) Peak vs Off-Peak Evaluator

    static func priceWindow(at date: Date = Date()) -> BeijingPriceWindow {
        let comps = beijingCalendar.dateComponents([.year, .month, .day, .weekday, .hour], from: date)
        guard let y = comps.year, let m = comps.month, let d = comps.day,
              let weekday = comps.weekday, let hour = comps.hour else {
            return .offPeak
        }

        if weekday == 1 || weekday == 7 {
            return .offPeak
        }

        let dateKey = String(format: "%04d-%02d-%02d", y, m, d)
        if chinaStatutoryHolidays.contains(dateKey) {
            return .offPeak
        }

        // 工作日忙时：09:00-12:00 及 14:00-18:00 (UTC+8)；其余含午休 12:00-14:00 均为闲时 5 折
        if (hour >= 9 && hour < 12) || (hour >= 14 && hour < 18) {
            return .peak
        }
        return .offPeak
    }

    static func priceWindow(unixMs: Int64) -> BeijingPriceWindow {
        guard unixMs > 0 else { return priceWindow(at: Date()) }
        return priceWindow(at: Date(timeIntervalSince1970: Double(unixMs) / 1000.0))
    }

    // MARK: - Exact RMB Unit Rates per Token

    static func unitRatesCNY(tier: DeepSeekModelTier, window: BeijingPriceWindow) -> TokenUnitRatesCNY? {
        switch (tier, window) {
        case (.flash, .offPeak):
            return TokenUnitRatesCNY(
                cacheHitPerToken: 0.00000002,  // ¥0.02 / M tokens
                cacheMissPerToken: 0.000001,   // ¥1.00 / M tokens
                outputPerToken: 0.000004       // ¥4.00 / M tokens
            )
        case (.flash, .peak):
            return TokenUnitRatesCNY(
                cacheHitPerToken: 0.00000004,  // ¥0.04 / M tokens
                cacheMissPerToken: 0.000002,   // ¥2.00 / M tokens
                outputPerToken: 0.000008       // ¥8.00 / M tokens
            )
        case (.v4Pro, .offPeak):
            return TokenUnitRatesCNY(
                cacheHitPerToken: 0.00000015,  // ¥0.15 / M tokens
                cacheMissPerToken: 0.0000045,  // ¥4.50 / M tokens
                outputPerToken: 0.0000135      // ¥13.50 / M tokens
            )
        case (.v4Pro, .peak):
            return TokenUnitRatesCNY(
                cacheHitPerToken: 0.00000030,  // ¥0.30 / M tokens
                cacheMissPerToken: 0.000009,   // ¥9.00 / M tokens
                outputPerToken: 0.000027       // ¥27.00 / M tokens
            )
        case (.other, _):
            return nil
        }
    }

    static func calculateRequestCostBreakdown(
        rawModelId: String,
        timestampMs: Int64,
        inputCacheHitTokens: Int64,
        inputCacheMissTokens: Int64,
        outputTokens: Int64,
        opencodeFallbackUsd: Double,
        usdToCnyRate: Double
    ) -> RequestCostBreakdown {
        let tier = classifyModel(rawModelId)
        let window = priceWindow(unixMs: timestampMs)
        let isOffPeak = (window == .offPeak)

        if let rates = unitRatesCNY(tier: tier, window: window) {
            let hitD = Double(max(0, inputCacheHitTokens))
            let missD = Double(max(0, inputCacheMissTokens))
            let outD = Double(max(0, outputTokens))

            let hitCost = hitD * rates.cacheHitPerToken
            let missCost = missD * rates.cacheMissPerToken
            let outCost = outD * rates.outputPerToken
            let total = hitCost + missCost + outCost

            if total > 0 {
                // 若这部分命中缓存的上下文没有走缓存，而按同时段未命中输入计价本需多付的净省金额
                let cacheSaved = hitD * max(0.0, rates.cacheMissPerToken - rates.cacheHitPerToken)
                // 若当前处于闲时 5 折窗口，对比忙时原价省下的净额（5 折即等于实际开销同额）
                let offPeakSaved: Double
                if isOffPeak, let peakRates = unitRatesCNY(tier: tier, window: .peak) {
                    let peakTotal = hitD * peakRates.cacheHitPerToken
                        + missD * peakRates.cacheMissPerToken
                        + outD * peakRates.outputPerToken
                    offPeakSaved = max(0.0, peakTotal - total)
                } else {
                    offPeakSaved = 0.0
                }

                return RequestCostBreakdown(
                    totalCostCny: total,
                    hitCostCny: hitCost,
                    missCostCny: missCost,
                    outputCostCny: outCost,
                    cacheSavedCny: cacheSaved,
                    offPeakSavedCny: offPeakSaved,
                    isOffPeak: isOffPeak
                )
            }
        }

        let fallbackCny = max(0.0, opencodeFallbackUsd) * max(1.0, usdToCnyRate)
        return RequestCostBreakdown(
            totalCostCny: fallbackCny,
            hitCostCny: 0.0,
            missCostCny: fallbackCny,
            outputCostCny: 0.0,
            cacheSavedCny: 0.0,
            offPeakSavedCny: 0.0,
            isOffPeak: isOffPeak
        )
    }

    static func formatMoney(
        amountCny: Double,
        mode: CurrencyDisplayMode,
        usdToCnyRate: Double,
        highPrecision: Bool = false
    ) -> String {
        let safeRate = max(1.0, usdToCnyRate)
        switch mode {
        case .cny:
            if highPrecision || (amountCny > 0 && amountCny < 0.1) {
                return String(format: "¥%.4f", amountCny)
            }
            return String(format: "¥%.2f", amountCny)
        case .usd:
            let usd = amountCny / safeRate
            if highPrecision || (usd > 0 && usd < 0.1) {
                return String(format: "$%.4f", usd)
            }
            return String(format: "$%.2f", usd)
        }
    }

    // MARK: - Online Accessible USD -> CNY Exchange Rate API (3-Tier Mainland & Global Failover)

    static func fetchLiveUsdToCnyRate(completion: @escaping (Double, String) -> Void) {
        let jsdelivrURL = URL(string: "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json")!
        let openErURL = URL(string: "https://open.er-api.com/v6/latest/USD")!
        let frankfurterURL = URL(string: "https://api.frankfurter.dev/v1/latest?base=USD&symbols=CNY")!

        fetchJSON(url: jsdelivrURL, timeout: 4.0) { json in
            if let usdDict = json?["usd"] as? [String: Any],
               let cny = (usdDict["cny"] as? NSNumber)?.doubleValue,
               cny > 5.0 && cny < 10.0 {
                DispatchQueue.main.async { completion(cny, "实时汇率") }
                return
            }

            fetchJSON(url: openErURL, timeout: 4.0) { json2 in
                if let rates = json2?["rates"] as? [String: Any],
                   let cny = (rates["CNY"] as? NSNumber)?.doubleValue,
                   cny > 5.0 && cny < 10.0 {
                    DispatchQueue.main.async { completion(cny, "实时汇率") }
                    return
                }

                fetchJSON(url: frankfurterURL, timeout: 4.0) { json3 in
                    if let rates = json3?["rates"] as? [String: Any],
                       let cny = (rates["CNY"] as? NSNumber)?.doubleValue,
                       cny > 5.0 && cny < 10.0 {
                        DispatchQueue.main.async { completion(cny, "实时汇率") }
                    }
                }
            }
        }
    }

    private static func fetchJSON(url: URL, timeout: TimeInterval, completion: @escaping ([String: Any]?) -> Void) {
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil)
                return
            }
            completion(obj)
        }.resume()
    }

    // MARK: - Official DeepSeek CSV Parser (Supports amount-*.csv & cost-*.csv with UTF-8 BOM)

    static func parseOfficialCSVFiles(urls: [URL]) -> OfficialCSVReconciliation? {
        guard !urls.isEmpty else { return nil }

        var hitTokens: Int64 = 0
        var missTokens: Int64 = 0
        var outTokens: Int64 = 0
        var reqCount: Int = 0

        var unitHitPrice: Double?
        var unitMissPrice: Double?
        var unitOutPrice: Double?

        var computedAmountCostCny: Double = 0.0
        var explicitCostFileSum: Double = 0.0
        var hasCostFile = false
        var hasAmountFile = false

        var detectedModel = "deepseek-flash"
        var detectedKeyName = ""
        var detectedMaskedKey = ""
        var detectedWalletType = "Paid"
        var detectedCurrency = "CNY"
        var minStartIso = ""
        var maxEndIso = ""
        var importedNames: [String] = []

        let bomAndWhitespace = CharacterSet(charactersIn: "\u{FEFF}\r\n\t ")

        for url in urls {
            guard let rawText = try? String(contentsOf: url, encoding: .utf8) else { continue }
            importedNames.append(url.lastPathComponent)

            let lines = rawText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: bomAndWhitespace) }
                .filter { !$0.isEmpty }

            guard lines.count >= 2 else { continue }
            let headers = lines[0].split(separator: ",", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: bomAndWhitespace).lowercased()
            }

            let colIdx = Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($1, $0) })

            if let typeCol = colIdx["type"], let amountCol = colIdx["amount"] {
                hasAmountFile = true
                let priceCol = colIdx["price"]
                let modelCol = colIdx["model"]
                let keyNameCol = colIdx["api_key_name"]
                let keyCol = colIdx["api_key"]
                let startCol = colIdx["start_time_iso"]
                let endCol = colIdx["end_time_iso"]

                for line in lines.dropFirst() {
                    let cols = splitCSVRow(line)
                    guard cols.count > max(typeCol, amountCol) else { continue }

                    let rowType = cols[typeCol]
                    let amountVal = Double(cols[amountCol]) ?? 0.0
                    let priceVal = priceCol.flatMap { cols.count > $0 ? Double(cols[$0]) : nil }

                    if let mCol = modelCol, cols.count > mCol, !cols[mCol].isEmpty {
                        detectedModel = cols[mCol]
                    }
                    if let knCol = keyNameCol, cols.count > knCol, !cols[knCol].isEmpty {
                        detectedKeyName = cols[knCol]
                    }
                    if let kCol = keyCol, cols.count > kCol, !cols[kCol].isEmpty {
                        detectedMaskedKey = cols[kCol]
                    }
                    if let sCol = startCol, cols.count > sCol, !cols[sCol].isEmpty {
                        if minStartIso.isEmpty || cols[sCol] < minStartIso { minStartIso = cols[sCol] }
                    }
                    if let eCol = endCol, cols.count > eCol, !cols[eCol].isEmpty {
                        if maxEndIso.isEmpty || cols[eCol] > maxEndIso { maxEndIso = cols[eCol] }
                    }

                    switch rowType {
                    case "input_cache_hit_tokens":
                        hitTokens += Int64(amountVal.rounded())
                        if let p = priceVal {
                            unitHitPrice = p
                            computedAmountCostCny += amountVal * p
                        }
                    case "input_cache_miss_tokens":
                        missTokens += Int64(amountVal.rounded())
                        if let p = priceVal {
                            unitMissPrice = p
                            computedAmountCostCny += amountVal * p
                        }
                    case "output_tokens":
                        outTokens += Int64(amountVal.rounded())
                        if let p = priceVal {
                            unitOutPrice = p
                            computedAmountCostCny += amountVal * p
                        }
                    case "request_count":
                        reqCount += Int(amountVal.rounded())
                    default:
                        break
                    }
                }
            } else if let costCol = colIdx["cost"] {
                hasCostFile = true
                let walletCol = colIdx["wallet_type"]
                let currCol = colIdx["currency"]
                let modelCol = colIdx["model"]
                let startCol = colIdx["start_time_iso"]
                let endCol = colIdx["end_time_iso"]

                for line in lines.dropFirst() {
                    let cols = splitCSVRow(line)
                    guard cols.count > costCol else { continue }

                    explicitCostFileSum += Double(cols[costCol]) ?? 0.0
                    if let wCol = walletCol, cols.count > wCol, !cols[wCol].isEmpty {
                        detectedWalletType = cols[wCol]
                    }
                    if let cCol = currCol, cols.count > cCol, !cols[cCol].isEmpty {
                        detectedCurrency = cols[cCol].uppercased()
                    }
                    if let mCol = modelCol, cols.count > mCol, !cols[mCol].isEmpty {
                        detectedModel = cols[mCol]
                    }
                    if let sCol = startCol, cols.count > sCol, !cols[sCol].isEmpty {
                        if minStartIso.isEmpty || cols[sCol] < minStartIso { minStartIso = cols[sCol] }
                    }
                    if let eCol = endCol, cols.count > eCol, !cols[eCol].isEmpty {
                        if maxEndIso.isEmpty || cols[eCol] > maxEndIso { maxEndIso = cols[eCol] }
                    }
                }
            }
        }

        guard hasAmountFile || hasCostFile else { return nil }

        let finalCost = hasCostFile ? explicitCostFileSum : computedAmountCostCny
        let shortStart = minStartIso.count >= 16 ? String(minStartIso.prefix(16)).replacingOccurrences(of: "T", with: " ") : minStartIso
        let shortEnd = maxEndIso.count >= 16 ? String(maxEndIso.dropFirst(11).prefix(5)) : maxEndIso
        let rangeStr = (!shortStart.isEmpty && !shortEnd.isEmpty) ? "\(shortStart)-\(shortEnd)" : "官方账单"

        return OfficialCSVReconciliation(
            importedFileNames: importedNames,
            modelName: detectedModel,
            apiKeyName: detectedKeyName.isEmpty ? "官方导出" : detectedKeyName,
            maskedApiKey: detectedMaskedKey,
            walletType: detectedWalletType,
            currency: detectedCurrency,
            inputCacheHitTokens: hitTokens,
            inputCacheMissTokens: missTokens,
            outputTokens: outTokens,
            requestCount: reqCount,
            unitHitPriceCny: unitHitPrice,
            unitMissPriceCny: unitMissPrice,
            unitOutputPriceCny: unitOutPrice,
            totalCostInOriginalCurrency: finalCost,
            timeRangeLabel: rangeStr
        )
    }

    private static func splitCSVRow(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return result
    }
}
