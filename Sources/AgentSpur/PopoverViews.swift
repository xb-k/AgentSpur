import AppKit
import Foundation
import QuartzCore
import UniformTypeIdentifiers

// MARK: - Cache Hit Visual Progress Track (CoreGraphics · Zero WebView)

private final class CacheProgressTrackView: NSView {
    var hitRatio: Double = 0.0 {
        didSet {
            let clamped = max(0.0, min(1.0, hitRatio))
            if abs(clamped - oldValue) > 0.0005 {
                needsDisplay = true
            }
        }
    }
    var hasTraffic: Bool = false {
        didSet {
            if hasTraffic != oldValue {
                needsDisplay = true
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let b = bounds
        let r = b.height * 0.5
        let trackPath = CGPath(roundedRect: b, cornerWidth: r, cornerHeight: r, transform: nil)

        ctx.saveGState()
        ctx.addPath(trackPath)
        ctx.clip()

        let missColor = hasTraffic
            ? NSColor(srgbRed: 0.96, green: 0.84, blue: 0.66, alpha: 0.72).cgColor
            : NSColor(srgbRed: 0.89, green: 0.92, blue: 0.96, alpha: 1.0).cgColor
        ctx.setFillColor(missColor)
        ctx.fill(b)

        if hasTraffic && hitRatio > 0.0 {
            let fillW = max(r * 2.0, b.width * CGFloat(max(0.0, min(1.0, hitRatio))))
            let fillRect = CGRect(x: 0, y: 0, width: min(b.width, fillW), height: b.height)
            let fillPath = CGPath(roundedRect: fillRect, cornerWidth: r, cornerHeight: r, transform: nil)

            ctx.saveGState()
            ctx.addPath(fillPath)
            ctx.clip()
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = [
                NSColor(srgbRed: 0.01, green: 0.52, blue: 0.78, alpha: 1.0).cgColor,
                NSColor(srgbRed: 0.04, green: 0.66, blue: 0.50, alpha: 1.0).cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: fillRect.maxX, y: 0),
                    options: []
                )
            }
            ctx.restoreGState()
        }

        ctx.restoreGState()
    }
}

// MARK: - Structured 2x2 Metric Sub-Tile View

private final class MetricTileView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")
    private let primaryValueLabel = NSTextField(labelWithString: "")
    private let subDetailLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor(srgbRed: 0.966, green: 0.979, blue: 0.994, alpha: 1.0).cgColor
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor(srgbRed: 0.85, green: 0.90, blue: 0.96, alpha: 1.0).cgColor

        titleLabel.font = NSFont.systemFont(ofSize: 10.0, weight: .semibold)
        titleLabel.textColor = NSColor(srgbRed: 0.30, green: 0.38, blue: 0.48, alpha: 1.0)
        titleLabel.lineBreakMode = .byTruncatingTail

        badgeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
        badgeLabel.textColor = NSColor(srgbRed: 0.02, green: 0.45, blue: 0.68, alpha: 1.0)
        badgeLabel.alignment = .right
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        primaryValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13.0, weight: .semibold)
        primaryValueLabel.textColor = NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)
        primaryValueLabel.lineBreakMode = .byTruncatingTail

        subDetailLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9.8, weight: .regular)
        subDetailLabel.textColor = NSColor(srgbRed: 0.34, green: 0.42, blue: 0.52, alpha: 1.0)
        subDetailLabel.lineBreakMode = .byTruncatingTail

        let topRow = NSStackView(views: [titleLabel, NSView(), badgeLabel])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 4

        let vStack = NSStackView(views: [topRow, primaryValueLabel, subDetailLabel])
        vStack.orientation = .vertical
        vStack.alignment = .width
        vStack.spacing = 2
        vStack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        vStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(vStack)

        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: topAnchor),
            vStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            vStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(title: String, badge: String, primary: String, sub: String, badgeColor: NSColor? = nil) {
        titleLabel.stringValue = title
        badgeLabel.stringValue = badge
        if let badgeColor {
            badgeLabel.textColor = badgeColor
        }
        primaryValueLabel.stringValue = primary
        subDetailLabel.stringValue = sub
    }
}

// MARK: - Subtle Tinted Tag View (6pt Rounded)

private final class SoftTagBadgeView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(bgColor: NSColor, borderColor: NSColor, textColor: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = bgColor.cgColor
        layer?.borderWidth = 1.0
        layer?.borderColor = borderColor.cgColor

        label.font = NSFont.monospacedDigitSystemFont(ofSize: 9.8, weight: .semibold)
        label.textColor = textColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2.0),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2.0),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6.0),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6.0)
        ])

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyColors(bg: NSColor, border: NSColor, text: NSColor) {
        layer?.backgroundColor = bg.cgColor
        layer?.borderColor = border.cgColor
        label.textColor = text
    }

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }
}

// MARK: - Today Official CSV & Cache Efficiency Telemetry Card View

final class BillingTelemetryCardView: NSView {
    private let eyebrowLabel = NSTextField(labelWithString: "")
    private let heroPrimaryCostLabel = NSTextField(labelWithString: "")
    private let heroSecondaryCostLabel = NSTextField(labelWithString: "")
    private let heroPeriodSplitLabel = NSTextField(labelWithString: "")

    private let savingsTag = SoftTagBadgeView(
        bgColor: NSColor(srgbRed: 0.925, green: 0.992, blue: 0.960, alpha: 1.0),
        borderColor: NSColor(srgbRed: 0.65, green: 0.93, blue: 0.81, alpha: 1.0),
        textColor: NSColor(srgbRed: 0.02, green: 0.47, blue: 0.34, alpha: 1.0)
    )
    private let windowModelTag = SoftTagBadgeView(
        bgColor: NSColor(srgbRed: 0.94, green: 0.976, blue: 1.0, alpha: 1.0),
        borderColor: NSColor(srgbRed: 0.73, green: 0.90, blue: 0.99, alpha: 1.0),
        textColor: NSColor(srgbRed: 0.01, green: 0.41, blue: 0.63, alpha: 1.0)
    )

    private let cacheBarLeftLabel = NSTextField(labelWithString: "")
    private let cacheBarRightLabel = NSTextField(labelWithString: "")
    private let cacheProgressTrack = CacheProgressTrackView()

    private let hitTile = MetricTileView()
    private let missTile = MetricTileView()
    private let outTile = MetricTileView()
    private let reqTile = MetricTileView()

    private let footerLeftLabel = NSTextField(labelWithString: "")
    private let footerRightLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.backgroundColor = NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.98).cgColor
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor(srgbRed: 0.82, green: 0.88, blue: 0.95, alpha: 1.0).cgColor

        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        // 1. Hero Spend, Peak/Off-Peak Split & Savings Tags
        eyebrowLabel.font = NSFont.systemFont(ofSize: 10.2, weight: .medium)
        eyebrowLabel.textColor = NSColor(srgbRed: 0.35, green: 0.42, blue: 0.52, alpha: 1.0)
        eyebrowLabel.lineBreakMode = .byTruncatingTail

        heroPrimaryCostLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 19.0, weight: .bold)
        heroPrimaryCostLabel.textColor = NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)

        heroSecondaryCostLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        heroSecondaryCostLabel.textColor = NSColor(srgbRed: 0.36, green: 0.44, blue: 0.54, alpha: 1.0)

        heroPeriodSplitLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9.8, weight: .medium)
        heroPeriodSplitLabel.textColor = NSColor(srgbRed: 0.26, green: 0.35, blue: 0.46, alpha: 1.0)
        heroPeriodSplitLabel.lineBreakMode = .byTruncatingTail

        let heroAmountRow = NSStackView(views: [heroPrimaryCostLabel, heroSecondaryCostLabel])
        heroAmountRow.orientation = .horizontal
        heroAmountRow.alignment = .lastBaseline
        heroAmountRow.spacing = 6

        let heroLeftStack = NSStackView(views: [eyebrowLabel, heroAmountRow, heroPeriodSplitLabel])
        heroLeftStack.orientation = .vertical
        heroLeftStack.alignment = .leading
        heroLeftStack.spacing = 1.5
        heroLeftStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let heroRightStack = NSStackView(views: [savingsTag, windowModelTag])
        heroRightStack.orientation = .vertical
        heroRightStack.alignment = .trailing
        heroRightStack.spacing = 4

        let heroRow = NSStackView(views: [heroLeftStack, NSView(), heroRightStack])
        heroRow.orientation = .horizontal
        heroRow.alignment = .centerY
        heroRow.spacing = 6

        // 2. Cache Efficiency Bar Section
        cacheBarLeftLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.2, weight: .semibold)
        cacheBarLeftLabel.textColor = NSColor(srgbRed: 0.02, green: 0.45, blue: 0.66, alpha: 1.0)

        cacheBarRightLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9.8, weight: .medium)
        cacheBarRightLabel.textColor = NSColor(srgbRed: 0.32, green: 0.40, blue: 0.50, alpha: 1.0)
        cacheBarRightLabel.alignment = .right

        let cacheHeaderRow = NSStackView(views: [cacheBarLeftLabel, NSView(), cacheBarRightLabel])
        cacheHeaderRow.orientation = .horizontal
        cacheHeaderRow.alignment = .centerY

        cacheProgressTrack.translatesAutoresizingMaskIntoConstraints = false
        cacheProgressTrack.heightAnchor.constraint(equalToConstant: 6.5).isActive = true

        let cacheSection = NSStackView(views: [cacheHeaderRow, cacheProgressTrack])
        cacheSection.orientation = .vertical
        cacheSection.alignment = .width
        cacheSection.spacing = 3.5

        // 3. 2x2 Structured Telemetry Tiles
        let gridRow1 = NSStackView(views: [hitTile, missTile])
        gridRow1.orientation = .horizontal
        gridRow1.distribution = .fillEqually
        gridRow1.spacing = 6

        let gridRow2 = NSStackView(views: [outTile, reqTile])
        gridRow2.orientation = .horizontal
        gridRow2.distribution = .fillEqually
        gridRow2.spacing = 6

        // 4. Footer Reconciliation & Exchange Rate Strip
        footerLeftLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9.6, weight: .regular)
        footerLeftLabel.textColor = NSColor(srgbRed: 0.34, green: 0.42, blue: 0.52, alpha: 1.0)
        footerLeftLabel.lineBreakMode = .byTruncatingTail
        footerLeftLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        footerRightLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9.6, weight: .semibold)
        footerRightLabel.textColor = NSColor(srgbRed: 0.20, green: 0.28, blue: 0.38, alpha: 1.0)
        footerRightLabel.alignment = .right
        footerRightLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let footerRow = NSStackView(views: [footerLeftLabel, NSView(), footerRightLabel])
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        footerRow.spacing = 6

        let cardDivider = NSView()
        cardDivider.wantsLayer = true
        cardDivider.layer?.backgroundColor = NSColor(srgbRed: 0.88, green: 0.92, blue: 0.97, alpha: 1.0).cgColor
        cardDivider.translatesAutoresizingMaskIntoConstraints = false
        cardDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let rootStack = NSStackView(views: [
            heroRow,
            cacheSection,
            gridRow1,
            gridRow2,
            cardDivider,
            footerRow
        ])
        rootStack.orientation = .vertical
        rootStack.alignment = .width
        rootStack.spacing = 6.5
        rootStack.edgeInsets = NSEdgeInsets(top: 9, left: 11, bottom: 8, right: 11)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        billing: BillingTelemetrySummary,
        csvReconciliation: OfficialCSVReconciliation?,
        currencyMode: CurrencyDisplayMode,
        usdToCnyRate: Double,
        currentWindow: BeijingPriceWindow
    ) {
        let safeRate = max(1.0, usdToCnyRate)

        if let csv = csvReconciliation {
            let tier = DeepSeekPricingEngine.classifyModel(csv.modelName)
            let costCny = csv.currency == "USD" ? csv.totalCostInOriginalCurrency * safeRate : csv.totalCostInOriginalCurrency

            eyebrowLabel.stringValue = "官方 CSV 对账 · [\(csv.apiKeyName)] · \(csv.timeRangeLabel)"
            heroPrimaryCostLabel.stringValue = DeepSeekPricingEngine.formatMoney(
                amountCny: costCny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: true
            )
            let altMode = currencyMode.next
            heroSecondaryCostLabel.stringValue = "≈ " + DeepSeekPricingEngine.formatMoney(
                amountCny: costCny,
                mode: altMode,
                usdToCnyRate: safeRate,
                highPrecision: true
            )
            heroPeriodSplitLabel.stringValue = "官方导出明细 · 钱包 \(csv.walletType)(\(csv.currency)) · Key \(csv.maskedApiKey)"

            let savedStr = DeepSeekPricingEngine.formatMoney(
                amountCny: csv.estimatedCacheSavedCny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: false
            )
            savingsTag.text = "Cache 已省 \(savedStr)"
            windowModelTag.applyColors(
                bg: NSColor(srgbRed: 0.94, green: 0.976, blue: 1.0, alpha: 1.0),
                border: NSColor(srgbRed: 0.73, green: 0.90, blue: 0.99, alpha: 1.0),
                text: NSColor(srgbRed: 0.01, green: 0.41, blue: 0.63, alpha: 1.0)
            )
            windowModelTag.text = "\(tier.canonicalModelId) · 官方账单"

            let hitPct = csv.cacheHitRatePercent
            cacheBarLeftLabel.stringValue = String(
                format: "Cache 命中率 %.1f%% · 总输入 %@",
                hitPct,
                TimeFormatters.formatTokenCount(csv.totalInputTokens)
            )
            cacheBarRightLabel.stringValue = "命中 \(TimeFormatters.formatTokenCount(csv.inputCacheHitTokens)) / 未命中 \(TimeFormatters.formatTokenCount(csv.inputCacheMissTokens))"
            cacheProgressTrack.hasTraffic = csv.totalInputTokens > 0
            cacheProgressTrack.hitRatio = hitPct / 100.0

            let hitUnit = csv.unitHitPriceCny.map { String(format: "¥%.2f/M", $0 * 1_000_000) } ?? "官方单价"
            let missUnit = csv.unitMissPriceCny.map { String(format: "¥%.2f/M", $0 * 1_000_000) } ?? "官方单价"
            let outUnit = csv.unitOutputPriceCny.map { String(format: "¥%.2f/M", $0 * 1_000_000) } ?? "官方单价"

            let csvHitCost = Double(csv.inputCacheHitTokens) * (csv.unitHitPriceCny ?? 0)
            let csvMissCost = Double(csv.inputCacheMissTokens) * (csv.unitMissPriceCny ?? 0)
            let csvOutCost = Double(csv.outputTokens) * (csv.unitOutputPriceCny ?? 0)

            hitTile.update(
                title: "缓存命中 · Hit",
                badge: hitUnit,
                primary: "\(TimeFormatters.formatTokenCount(csv.inputCacheHitTokens)) (\(String(format: "%.1f%%", hitPct)))",
                sub: String(format: "账单单项 ¥%.4f", csvHitCost),
                badgeColor: NSColor(srgbRed: 0.02, green: 0.50, blue: 0.36, alpha: 1.0)
            )
            missTile.update(
                title: "未命中 · Miss",
                badge: missUnit,
                primary: "\(TimeFormatters.formatTokenCount(csv.inputCacheMissTokens)) (\(String(format: "%.1f%%", max(0, 100 - hitPct))))",
                sub: String(format: "账单单项 ¥%.4f", csvMissCost),
                badgeColor: NSColor(srgbRed: 0.72, green: 0.38, blue: 0.04, alpha: 1.0)
            )
            outTile.update(
                title: "输出+推理 · Output",
                badge: outUnit,
                primary: TimeFormatters.formatTokenCount(csv.outputTokens),
                sub: String(format: "账单单项 ¥%.4f", csvOutCost)
            )
            let avgCsv = csv.requestCount > 0 ? costCny / Double(csv.requestCount) : 0.0
            reqTile.update(
                title: "总请求 · Requests",
                badge: csv.walletType,
                primary: "\(TimeFormatters.formatIntWithCommas(csv.requestCount)) 次",
                sub: String(format: "均次 ¥%.4f", avgCsv)
            )

            footerLeftLabel.stringValue = String(
                format: "对比本地 %@ 库内精算 ¥%.4f",
                billing.dateLabel,
                billing.spurCostCny
            )
            footerRightLabel.stringValue = String(format: "汇率 $1 = ¥%.4f", safeRate)
        } else {
            let tier = DeepSeekPricingEngine.classifyModel(billing.dominantModelId)
            let rates = DeepSeekPricingEngine.unitRatesCNY(tier: tier, window: currentWindow)

            eyebrowLabel.stringValue = "\(billing.dateLabel) 全量精算 · \(tier.specSummary)"
            heroPrimaryCostLabel.stringValue = DeepSeekPricingEngine.formatMoney(
                amountCny: billing.spurCostCny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: true
            )
            let altMode = currencyMode.next
            heroSecondaryCostLabel.stringValue = "≈ " + DeepSeekPricingEngine.formatMoney(
                amountCny: billing.spurCostCny,
                mode: altMode,
                usdToCnyRate: safeRate,
                highPrecision: true
            )

            let peakMoney = DeepSeekPricingEngine.formatMoney(
                amountCny: billing.peakCostCny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: billing.peakCostCny > 0 && billing.peakCostCny < 0.1
            )
            let offPeakMoney = DeepSeekPricingEngine.formatMoney(
                amountCny: billing.offPeakCostCny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: billing.offPeakCostCny > 0 && billing.offPeakCostCny < 0.1
            )
            heroPeriodSplitLabel.stringValue = "忙时原价 \(peakMoney) (\(billing.peakRequestCount)次) · 闲时5折 \(offPeakMoney) (\(billing.offPeakRequestCount)次)"

            let cacheSavedText = DeepSeekPricingEngine.formatMoney(
                amountCny: billing.cacheSavedCny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: false
            )
            if billing.offPeakSavedCny >= 0.01 {
                let offSavedText = DeepSeekPricingEngine.formatMoney(
                    amountCny: billing.offPeakSavedCny,
                    mode: currencyMode,
                    usdToCnyRate: safeRate,
                    highPrecision: false
                )
                savingsTag.text = "缓省 \(cacheSavedText) · 闲省 \(offSavedText)"
            } else {
                savingsTag.text = "Cache 已省 \(cacheSavedText)"
            }

            if currentWindow == .peak {
                windowModelTag.applyColors(
                    bg: NSColor(srgbRed: 1.0, green: 0.965, blue: 0.91, alpha: 1.0),
                    border: NSColor(srgbRed: 0.97, green: 0.82, blue: 0.58, alpha: 1.0),
                    text: NSColor(srgbRed: 0.72, green: 0.36, blue: 0.03, alpha: 1.0)
                )
            } else {
                windowModelTag.applyColors(
                    bg: NSColor(srgbRed: 0.94, green: 0.976, blue: 1.0, alpha: 1.0),
                    border: NSColor(srgbRed: 0.73, green: 0.90, blue: 0.99, alpha: 1.0),
                    text: NSColor(srgbRed: 0.01, green: 0.41, blue: 0.63, alpha: 1.0)
                )
            }
            windowModelTag.text = "\(tier.canonicalModelId) · 当前\(currentWindow.badgeText)"

            let hitPct = billing.cacheHitRatePercent
            cacheBarLeftLabel.stringValue = String(
                format: "Cache 命中率 %.1f%% · 总输入 %@",
                hitPct,
                TimeFormatters.formatTokenCount(billing.totalInputTokens)
            )
            cacheBarRightLabel.stringValue = "命中 \(TimeFormatters.formatTokenCount(billing.inputCacheHitTokens)) / 未命中 \(TimeFormatters.formatTokenCount(billing.inputCacheMissTokens))"
            cacheProgressTrack.hasTraffic = billing.totalInputTokens > 0
            cacheProgressTrack.hitRatio = hitPct / 100.0

            let hitUnitStr = rates.map { String(format: "当前 ¥%.2f/M", $0.hitPerMillion) } ?? "实时折算"
            let missUnitStr = rates.map { String(format: "当前 ¥%.2f/M", $0.missPerMillion) } ?? "实时折算"
            let outUnitStr = rates.map { String(format: "当前 ¥%.2f/M", $0.outPerMillion) } ?? "实时折算"

            let hitCostText = DeepSeekPricingEngine.formatMoney(
                amountCny: billing.cacheHitCostCny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: billing.cacheHitCostCny < 1.0
            )
            hitTile.update(
                title: "缓存命中 · Hit",
                badge: hitUnitStr,
                primary: "\(TimeFormatters.formatTokenCount(billing.inputCacheHitTokens)) (\(String(format: "%.1f%%", hitPct)))",
                sub: "实付 \(hitCostText) · 省98%输入单价",
                badgeColor: NSColor(srgbRed: 0.02, green: 0.50, blue: 0.36, alpha: 1.0)
            )

            let missCostText = DeepSeekPricingEngine.formatMoney(
                amountCny: billing.cacheMissCostCny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: billing.cacheMissCostCny < 1.0
            )
            let writeSuffix = billing.cacheWriteTokens > 0
                ? " · 写缓 \(TimeFormatters.formatTokenCount(billing.cacheWriteTokens))"
                : " · 新增上下文"
            missTile.update(
                title: "未命中 · Miss",
                badge: missUnitStr,
                primary: "\(TimeFormatters.formatTokenCount(billing.inputCacheMissTokens)) (\(String(format: "%.1f%%", billing.cacheMissRatePercent)))",
                sub: "实付 \(missCostText)\(writeSuffix)",
                badgeColor: NSColor(srgbRed: 0.72, green: 0.38, blue: 0.04, alpha: 1.0)
            )

            let outCostText = DeepSeekPricingEngine.formatMoney(
                amountCny: billing.outputCostCny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: billing.outputCostCny < 1.0
            )
            let reasonDetail = billing.reasoningTokens > 0
                ? "含思维链 \(TimeFormatters.formatTokenCount(billing.reasoningTokens))"
                : "标准输出+推理"
            outTile.update(
                title: "输出+推理 · Output",
                badge: outUnitStr,
                primary: TimeFormatters.formatTokenCount(billing.outputTokens),
                sub: "实付 \(outCostText) · \(reasonDetail)"
            )

            let avgCostText = DeepSeekPricingEngine.formatMoney(
                amountCny: billing.avgCostPerRequestCny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: true
            )
            reqTile.update(
                title: "时段分布 · Requests",
                badge: String(format: "闲时 %.0f%%", billing.offPeakRatePercent),
                primary: "\(TimeFormatters.formatIntWithCommas(billing.requestCount)) 次",
                sub: "忙\(billing.peakRequestCount) / 闲\(billing.offPeakRequestCount) · 均 \(avgCostText)"
            )

            let rawCny = billing.opencodeRawUsd * safeRate
            footerLeftLabel.stringValue = String(
                format: "opencode静态估 $%.4f (≈¥%.2f·全天按5折未计忙时)",
                billing.opencodeRawUsd,
                rawCny
            )
            footerRightLabel.stringValue = String(format: "汇率 $1 = ¥%.4f", safeRate)
        }
    }
}

// MARK: - Native CoreGraphics Today 24-Hour Interactive Chart View (Peak Shading + Hover Crosshair)

final class NativeTodayHourlyChartView: NSView {
    var points: [TodayHourlyPoint] = [] {
        didSet {
            if points != oldValue {
                needsDisplay = true
            }
        }
    }
    var metricKind: ChartMetricKind = .requests {
        didSet {
            if metricKind != oldValue {
                needsDisplay = true
            }
        }
    }

    private var hoveredHour: Int? {
        didSet {
            if hoveredHour != oldValue {
                needsDisplay = true
            }
        }
    }
    private var trackingAreaRef: NSTrackingArea?

    override var isFlipped: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let leftPad: CGFloat = 42
        let rightPad: CGFloat = 12
        let plotW = max(40, bounds.width - leftPad - rightPad)
        let stepX = plotW / 23.0
        guard pt.x >= leftPad - stepX * 0.5, pt.x <= leftPad + plotW + stepX * 0.5 else {
            hoveredHour = nil
            return
        }
        let rawIdx = Int(((pt.x - leftPad) / stepX).rounded())
        hoveredHour = max(0, min(23, rawIdx))
    }

    override func mouseExited(with event: NSEvent) {
        hoveredHour = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let bounds = self.bounds
        let bgPath = CGPath(roundedRect: bounds, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.addPath(bgPath)
        ctx.setFillColor(NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.98).cgColor)
        ctx.fillPath()

        ctx.addPath(bgPath)
        ctx.setStrokeColor(NSColor(srgbRed: 0.83, green: 0.89, blue: 0.95, alpha: 1.0).cgColor)
        ctx.setLineWidth(1.0)
        ctx.strokePath()

        guard points.count == 24 else { return }

        let leftPad: CGFloat = 42
        let rightPad: CGFloat = 12
        let bottomPad: CGFloat = 19
        let topPad: CGFloat = 12
        let plotW = max(40, bounds.width - leftPad - rightPad)
        let plotH = max(24, bounds.height - topPad - bottomPad)
        let stepX = plotW / 23.0

        // 1. 绘制北京时间忙时时段淡琥珀色底纹 (09:00-12:00 & 14:00-18:00)，直观呈现忙时2倍计价区间
        ctx.saveGState()
        ctx.setFillColor(NSColor(srgbRed: 0.96, green: 0.62, blue: 0.07, alpha: 0.065).cgColor)
        for (idx, pt) in points.enumerated() where pt.isPeakHour {
            let cx = leftPad + CGFloat(idx) * stepX
            let x0 = max(leftPad, cx - stepX * 0.5)
            let x1 = min(leftPad + plotW, cx + stepX * 0.5)
            ctx.fill(CGRect(x: x0, y: bottomPad, width: max(1, x1 - x0), height: plotH))
        }
        ctx.restoreGState()

        let rawValues: [Double] = points.map { pt in
            switch metricKind {
            case .requests: return Double(pt.requestCount)
            case .costCny:  return pt.costCny
            case .cacheHit: return pt.cacheHitPercent
            }
        }
        let rawMax = rawValues.max() ?? 0.0
        let maxVal: Double = {
            switch metricKind {
            case .requests: return max(rawMax, 1.0) * 1.16
            case .costCny:  return max(rawMax, 0.01) * 1.16
            case .cacheHit: return 105.0
            }
        }()

        // 2. 水平参考虚线
        ctx.saveGState()
        ctx.setStrokeColor(NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 0.065).cgColor)
        ctx.setLineWidth(1.0)
        ctx.setLineDash(phase: 0, lengths: [3, 3])
        for i in 0...2 {
            let y = bottomPad + plotH * (CGFloat(i) / 2.0)
            ctx.move(to: CGPoint(x: leftPad, y: y))
            ctx.addLine(to: CGPoint(x: leftPad + plotW, y: y))
        }
        ctx.strokePath()
        ctx.restoreGState()

        let coords: [CGPoint] = rawValues.enumerated().map { idx, v in
            let x = leftPad + CGFloat(idx) * stepX
            let y = bottomPad + CGFloat(min(1.0, v / maxVal)) * plotH
            return CGPoint(x: x, y: y)
        }

        let lineColor: NSColor = {
            switch metricKind {
            case .requests: return NSColor(srgbRed: 0.01, green: 0.52, blue: 0.78, alpha: 1.0)
            case .costCny:  return NSColor(srgbRed: 0.04, green: 0.59, blue: 0.41, alpha: 1.0)
            case .cacheHit: return NSColor(srgbRed: 0.03, green: 0.55, blue: 0.72, alpha: 1.0)
            }
        }()

        // 3. 渐变面积与平滑贝塞尔曲线
        let areaPath = CGMutablePath()
        areaPath.move(to: CGPoint(x: coords[0].x, y: bottomPad))
        areaPath.addLine(to: coords[0])
        for i in 1..<coords.count {
            let prev = coords[i - 1]
            let curr = coords[i]
            let midX = (prev.x + curr.x) * 0.5
            areaPath.addCurve(
                to: curr,
                control1: CGPoint(x: midX, y: prev.y),
                control2: CGPoint(x: midX, y: curr.y)
            )
        }
        areaPath.addLine(to: CGPoint(x: coords[23].x, y: bottomPad))
        areaPath.closeSubpath()

        ctx.saveGState()
        ctx.addPath(areaPath)
        ctx.clip()
        let cs = CGColorSpaceCreateDeviceRGB()
        let gradColors = [
            lineColor.withAlphaComponent(0.20).cgColor,
            lineColor.withAlphaComponent(0.01).cgColor
        ] as CFArray
        if let grad = CGGradient(colorsSpace: cs, colors: gradColors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: 0, y: bottomPad + plotH),
                end: CGPoint(x: 0, y: bottomPad),
                options: []
            )
        }
        ctx.restoreGState()

        let strokePath = CGMutablePath()
        strokePath.move(to: coords[0])
        for i in 1..<coords.count {
            let prev = coords[i - 1]
            let curr = coords[i]
            let midX = (prev.x + curr.x) * 0.5
            strokePath.addCurve(
                to: curr,
                control1: CGPoint(x: midX, y: prev.y),
                control2: CGPoint(x: midX, y: curr.y)
            )
        }
        ctx.addPath(strokePath)
        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(1.8)
        ctx.setLineCap(.round)
        ctx.strokePath()

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8.8, weight: .regular),
            .foregroundColor: NSColor(srgbRed: 0.36, green: 0.43, blue: 0.52, alpha: 1.0)
        ]
        let nowAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .semibold),
            .foregroundColor: lineColor
        ]

        let tickHours: Set<Int> = [0, 6, 9, 12, 14, 18, 23]
        for (idx, pt) in points.enumerated() {
            let c = coords[idx]
            let isHovered = (hoveredHour == idx)
            if isHovered || pt.isCurrentHour || pt.requestCount > 0 {
                let r: CGFloat = isHovered ? 3.6 : (pt.isCurrentHour ? 3.0 : 2.1)
                ctx.setFillColor((isHovered || pt.isCurrentHour) ? lineColor.cgColor : NSColor.white.cgColor)
                ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                ctx.setStrokeColor(lineColor.cgColor)
                ctx.setLineWidth(1.4)
                ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            }

            if tickHours.contains(pt.hour) {
                let str = "\(pt.hourLabel)h"
                let nsStr = NSString(string: str)
                let attrs = pt.isCurrentHour ? nowAttrs : labelAttrs
                let sz = nsStr.size(withAttributes: attrs)
                nsStr.draw(at: CGPoint(x: c.x - sz.width * 0.5, y: 3), withAttributes: attrs)
            }
        }

        // 4. Y 轴峰值与中位刻度
        let maxText: String
        let midText: String
        switch metricKind {
        case .requests:
            maxText = "\(Int(rawMax))次"
            midText = rawMax >= 2 ? "\(Int(rawMax / 2))次" : ""
        case .costCny:
            maxText = String(format: "¥%.2f", rawMax)
            midText = rawMax >= 0.02 ? String(format: "¥%.2f", rawMax * 0.5) : ""
        case .cacheHit:
            maxText = "100%"
            midText = "50%"
        }
        NSString(string: maxText).draw(at: CGPoint(x: 5, y: bottomPad + plotH - 9), withAttributes: labelAttrs)
        if !midText.isEmpty {
            NSString(string: midText).draw(at: CGPoint(x: 5, y: bottomPad + plotH * 0.5 - 5), withAttributes: labelAttrs)
        }
        NSString(string: "0").draw(at: CGPoint(x: 5, y: bottomPad - 3), withAttributes: labelAttrs)

        // 5. 鼠标悬停十字准星与实时分时浮窗读数
        if let hIdx = hoveredHour, hIdx >= 0, hIdx < points.count {
            let pt = points[hIdx]
            let cx = coords[hIdx].x
            ctx.saveGState()
            ctx.setStrokeColor(lineColor.withAlphaComponent(0.45).cgColor)
            ctx.setLineWidth(1.0)
            ctx.setLineDash(phase: 0, lengths: [2, 2])
            ctx.move(to: CGPoint(x: cx, y: bottomPad))
            ctx.addLine(to: CGPoint(x: cx, y: bottomPad + plotH))
            ctx.strokePath()
            ctx.restoreGState()

            let winTag = pt.isPeakHour ? "忙时原价" : "闲时5折"
            let infoStr = String(
                format: "%02d:00 (%@) · %d次 · ¥%.4f · 缓%.0f%%",
                pt.hour,
                winTag,
                pt.requestCount,
                pt.costCny,
                pt.cacheHitPercent
            )
            let pillAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9.2, weight: .semibold),
                .foregroundColor: NSColor(srgbRed: 0.07, green: 0.12, blue: 0.20, alpha: 1.0)
            ]
            let nsInfo = NSString(string: infoStr)
            let textSize = nsInfo.size(withAttributes: pillAttrs)
            let boxW = textSize.width + 10
            let boxH = textSize.height + 4
            let boxX = min(max(leftPad + 2, cx - boxW * 0.5), bounds.width - rightPad - boxW)
            let boxY = bounds.height - boxH - 3

            let boxRect = CGRect(x: boxX, y: boxY, width: boxW, height: boxH)
            let boxPath = CGPath(roundedRect: boxRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
            ctx.addPath(boxPath)
            ctx.setFillColor(NSColor(srgbRed: 0.95, green: 0.98, blue: 1.0, alpha: 0.96).cgColor)
            ctx.fillPath()
            ctx.addPath(boxPath)
            ctx.setStrokeColor(lineColor.withAlphaComponent(0.45).cgColor)
            ctx.setLineWidth(1.0)
            ctx.strokePath()

            nsInfo.draw(at: CGPoint(x: boxX + 5, y: boxY + 2), withAttributes: pillAttrs)
        } else if points.contains(where: { $0.isPeakHour }) {
            let legend = NSString(string: "浅橙底=工作日忙时")
            let legAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8.5, weight: .medium),
                .foregroundColor: NSColor(srgbRed: 0.68, green: 0.44, blue: 0.12, alpha: 0.85)
            ]
            let sz = legend.size(withAttributes: legAttrs)
            legend.draw(at: CGPoint(x: bounds.width - rightPad - sz.width - 2, y: bounds.height - sz.height - 3), withAttributes: legAttrs)
        }
    }
}

// MARK: - 2-Line Master Session Card + Collapsible Indented Sub-Agent Row View

final class SessionRowView: NSControl {
    var onClick: (() -> Void)?
    var onToggleCollapse: (() -> Void)?

    private(set) var boundState: AgentRunState = .completed
    private(set) var boundEnteredAtMs: Int64 = 0
    private(set) var isSubTaskRow = false

    private var cachedCostSuffix: String?
    private var cachedCacheBadgeSuffix: String?
    private var cachedDurationSuffix: String?
    private var cachedTerminalBadge: String?
    private var currentIsAutoFocused: Bool = false

    private let iconView = NSImageView()
    private let roleBadgeField = NSTextField(labelWithString: "")
    private let titleField = NSTextField(labelWithString: "")
    private let liveTimerField = NSTextField(labelWithString: "")
    private var collapseBtn: NSButton?

    // Master 第二行精细信息栏 / SubTask 单行右侧聚合信息栏
    private let subMetaLeftField = NSTextField(labelWithString: "")
    private let subMetaRightField = NSTextField(labelWithString: "")
    private let rightMetaField = NSTextField(labelWithString: "")

    init(isSubTask: Bool) {
        self.isSubTaskRow = isSubTask
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = isSubTask ? 7 : 9

        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        if isSubTask {
            let treeGlyph = NSTextField(labelWithString: "↳")
            treeGlyph.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)
            treeGlyph.textColor = NSColor(srgbRed: 0.48, green: 0.56, blue: 0.66, alpha: 1.0)
            treeGlyph.setContentCompressionResistancePriority(.required, for: .horizontal)

            roleBadgeField.font = NSFont.monospacedSystemFont(ofSize: 9.8, weight: .semibold)
            roleBadgeField.textColor = NSColor(srgbRed: 0.02, green: 0.45, blue: 0.68, alpha: 1.0)
            roleBadgeField.setContentCompressionResistancePriority(.required, for: .horizontal)

            rightMetaField.alignment = .right
            rightMetaField.setContentCompressionResistancePriority(.required, for: .horizontal)

            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: 13),
                iconView.heightAnchor.constraint(equalToConstant: 13)
            ])

            let hStack = NSStackView(views: [treeGlyph, iconView, roleBadgeField, titleField, NSView(), rightMetaField])
            hStack.orientation = .horizontal
            hStack.alignment = .centerY
            hStack.spacing = 4.5
            hStack.edgeInsets = NSEdgeInsets(top: 4.5, left: 14, bottom: 4.5, right: 8)
            hStack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hStack)

            NSLayoutConstraint.activate([
                heightAnchor.constraint(greaterThanOrEqualToConstant: 26),
                hStack.topAnchor.constraint(equalTo: topAnchor),
                hStack.leadingAnchor.constraint(equalTo: leadingAnchor),
                hStack.trailingAnchor.constraint(equalTo: trailingAnchor),
                hStack.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: 16),
                iconView.heightAnchor.constraint(equalToConstant: 16)
            ])

            liveTimerField.alignment = .right
            liveTimerField.setContentCompressionResistancePriority(.required, for: .horizontal)

            let cBtn = NSButton(title: "", target: self, action: #selector(handleCollapseButtonTap))
            cBtn.bezelStyle = .inline
            cBtn.controlSize = .mini
            cBtn.font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
            cBtn.isHidden = true
            cBtn.setContentCompressionResistancePriority(.required, for: .horizontal)
            cBtn.setContentHuggingPriority(.required, for: .horizontal)
            self.collapseBtn = cBtn

            let topLine = NSStackView(views: [iconView, titleField, NSView(), liveTimerField, cBtn])
            topLine.orientation = .horizontal
            topLine.alignment = .centerY
            topLine.spacing = 6

            subMetaLeftField.font = NSFont.monospacedDigitSystemFont(ofSize: 9.8, weight: .regular)
            subMetaLeftField.textColor = NSColor(srgbRed: 0.30, green: 0.38, blue: 0.48, alpha: 1.0)
            subMetaLeftField.lineBreakMode = .byTruncatingTail
            subMetaLeftField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            subMetaRightField.font = NSFont.monospacedDigitSystemFont(ofSize: 9.8, weight: .semibold)
            subMetaRightField.textColor = NSColor(srgbRed: 0.20, green: 0.29, blue: 0.40, alpha: 1.0)
            subMetaRightField.alignment = .right
            subMetaRightField.setContentCompressionResistancePriority(.required, for: .horizontal)

            let leadSpacer = NSView()
            leadSpacer.translatesAutoresizingMaskIntoConstraints = false
            leadSpacer.widthAnchor.constraint(equalToConstant: 16).isActive = true

            let bottomLine = NSStackView(views: [leadSpacer, subMetaLeftField, NSView(), subMetaRightField])
            bottomLine.orientation = .horizontal
            bottomLine.alignment = .centerY
            bottomLine.spacing = 6

            let vStack = NSStackView(views: [topLine, bottomLine])
            vStack.orientation = .vertical
            vStack.alignment = .width
            vStack.spacing = 2.5
            vStack.edgeInsets = NSEdgeInsets(top: 6, left: 9, bottom: 5.5, right: 9)
            vStack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(vStack)

            NSLayoutConstraint.activate([
                vStack.topAnchor.constraint(equalTo: topAnchor),
                vStack.leadingAnchor.constraint(equalTo: leadingAnchor),
                vStack.trailingAnchor.constraint(equalTo: trailingAnchor),
                vStack.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleCollapseButtonTap() {
        onToggleCollapse?()
    }

    func configureMaster(
        state: AgentRunState,
        enteredAtMs: Int64,
        sprite: NSImage,
        title: String,
        nowMs: Int64,
        metaSummaryLeft: String,
        terminalBadge: String,
        subTaskCount: Int,
        isCollapsed: Bool,
        isAutoFocused: Bool,
        tooltipText: String
    ) {
        self.boundState = state
        self.boundEnteredAtMs = enteredAtMs
        self.currentIsAutoFocused = isAutoFocused

        iconView.image = sprite
        self.toolTip = tooltipText

        titleField.font = NSFont.systemFont(ofSize: 12.3, weight: isAutoFocused ? .bold : .semibold)
        titleField.textColor = isAutoFocused
            ? NSColor(srgbRed: 0.02, green: 0.22, blue: 0.36, alpha: 1.0)
            : NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)
        titleField.stringValue = title

        subMetaLeftField.stringValue = metaSummaryLeft
        subMetaRightField.stringValue = terminalBadge

        if let cBtn = collapseBtn {
            if subTaskCount > 0 {
                cBtn.isHidden = false
                cBtn.title = isCollapsed ? "▸ \(subTaskCount)子" : "▾ \(subTaskCount)子"
            } else {
                cBtn.isHidden = true
            }
        }

        updateLiveTimerText(nowMs: nowMs)
        applyFocusAppearance(isAutoFocused: isAutoFocused)
    }

    func configureSubTask(
        state: AgentRunState,
        enteredAtMs: Int64,
        sprite: NSImage,
        roleLabel: String,
        title: String,
        nowMs: Int64,
        durationSuffix: String?,
        costSuffix: String?,
        cacheBadgeSuffix: String?,
        distinctTerminalBadge: String?,
        isAutoFocused: Bool,
        tooltipText: String
    ) {
        self.boundState = state
        self.boundEnteredAtMs = enteredAtMs
        self.cachedDurationSuffix = durationSuffix
        self.cachedCostSuffix = costSuffix
        self.cachedCacheBadgeSuffix = cacheBadgeSuffix
        self.cachedTerminalBadge = distinctTerminalBadge
        self.currentIsAutoFocused = isAutoFocused

        iconView.image = sprite
        self.toolTip = tooltipText

        roleBadgeField.stringValue = roleLabel
        titleField.font = NSFont.systemFont(ofSize: 11.3, weight: isAutoFocused ? .semibold : .regular)
        titleField.textColor = isAutoFocused
            ? NSColor(srgbRed: 0.02, green: 0.22, blue: 0.36, alpha: 1.0)
            : NSColor(srgbRed: 0.10, green: 0.15, blue: 0.24, alpha: 1.0)
        titleField.stringValue = title

        updateLiveTimerText(nowMs: nowMs)
        applyFocusAppearance(isAutoFocused: isAutoFocused)
    }

    func updateSpriteOnly(_ image: NSImage) {
        iconView.image = image
    }

    func updateLiveTimerText(nowMs: Int64) {
        let timerText = TimeFormatters.liveStateTimerLabel(
            state: boundState,
            enteredAtMs: boundEnteredAtMs,
            nowMs: nowMs
        )

        if !isSubTaskRow {
            liveTimerField.attributedStringValue = NSAttributedString(
                string: timerText,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 10.6, weight: .semibold),
                    .foregroundColor: boundState.accentColor
                ]
            )
            return
        }

        let sepAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9.2, weight: .regular),
            .foregroundColor: NSColor(srgbRed: 0.62, green: 0.69, blue: 0.77, alpha: 1.0)
        ]

        let combined = NSMutableAttributedString()
        if let cost = cachedCostSuffix {
            combined.append(NSAttributedString(
                string: cost,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 10.0, weight: .medium),
                    .foregroundColor: NSColor(srgbRed: 0.18, green: 0.26, blue: 0.36, alpha: 1.0)
                ]
            ))
            combined.append(NSAttributedString(string: " · ", attributes: sepAttrs))
        }
        if let cacheBadge = cachedCacheBadgeSuffix {
            combined.append(NSAttributedString(
                string: cacheBadge,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9.6, weight: .medium),
                    .foregroundColor: NSColor(srgbRed: 0.02, green: 0.48, blue: 0.40, alpha: 1.0)
                ]
            ))
            combined.append(NSAttributedString(string: " · ", attributes: sepAttrs))
        }
        if let dur = cachedDurationSuffix {
            combined.append(NSAttributedString(
                string: dur,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9.6, weight: .regular),
                    .foregroundColor: NSColor(srgbRed: 0.40, green: 0.47, blue: 0.56, alpha: 1.0)
                ]
            ))
            combined.append(NSAttributedString(string: " · ", attributes: sepAttrs))
        }
        combined.append(NSAttributedString(
            string: timerText,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10.2, weight: .semibold),
                .foregroundColor: boundState.accentColor
            ]
        ))
        if let termBadge = cachedTerminalBadge, !termBadge.isEmpty {
            combined.append(NSAttributedString(string: " · ", attributes: sepAttrs))
            combined.append(NSAttributedString(
                string: termBadge,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9.6, weight: .medium),
                    .foregroundColor: NSColor(srgbRed: 0.26, green: 0.35, blue: 0.46, alpha: 1.0)
                ]
            ))
        }
        rightMetaField.attributedStringValue = combined
    }

    private func applyFocusAppearance(isAutoFocused: Bool) {
        guard let layer = self.layer else { return }
        layer.removeAnimation(forKey: "focusBorderBlink")

        if isAutoFocused {
            layer.backgroundColor = NSColor(srgbRed: 0.915, green: 0.968, blue: 1.0, alpha: 0.98).cgColor
            layer.borderWidth = 1.3
            let strong = NSColor(srgbRed: 0.01, green: 0.52, blue: 0.78, alpha: 0.92).cgColor
            let faint = NSColor(srgbRed: 0.06, green: 0.65, blue: 0.91, alpha: 0.22).cgColor
            layer.borderColor = strong

            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let anim = CABasicAnimation(keyPath: "borderColor")
                anim.fromValue = strong
                anim.toValue = faint
                anim.duration = 0.68
                anim.autoreverses = true
                anim.repeatCount = .infinity
                anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(anim, forKey: "focusBorderBlink")
            }
        } else {
            layer.backgroundColor = isSubTaskRow
                ? NSColor(srgbRed: 0.968, green: 0.982, blue: 0.996, alpha: 0.96).cgColor
                : NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.98).cgColor
            layer.borderWidth = 1.0
            layer.borderColor = isSubTaskRow
                ? NSColor(srgbRed: 0.86, green: 0.91, blue: 0.96, alpha: 1.0).cgColor
                : NSColor(srgbRed: 0.82, green: 0.88, blue: 0.95, alpha: 1.0).cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if let cBtn = collapseBtn, !cBtn.isHidden {
            let btnPt = cBtn.convert(pt, from: self)
            if cBtn.bounds.insetBy(dx: -4, dy: -4).contains(btnPt) {
                super.mouseDown(with: event)
                return
            }
        }
        layer?.backgroundColor = NSColor(srgbRed: 0.89, green: 0.96, blue: 1.0, alpha: 0.98).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        applyFocusAppearance(isAutoFocused: currentIsAutoFocused)
        let pt = convert(event.locationInWindow, from: nil)
        if let cBtn = collapseBtn, !cBtn.isHidden {
            let btnPt = cBtn.convert(pt, from: self)
            if cBtn.bounds.insetBy(dx: -4, dy: -4).contains(btnPt) {
                onToggleCollapse?()
                return
            }
        }
        if bounds.contains(pt) {
            onClick?()
        }
    }
}

// MARK: - Bright Minimalist Status Bar Popover Controller

final class StatusPopoverViewController: NSViewController {
    var onRefreshQuota: (() -> Void)?
    var onToggleCurrencyMode: (() -> Void)?
    var onToggleSilentAlert: ((Bool) -> Void)?
    var onToggleAutoFocus: ((Bool) -> Void)?
    var onSelectRealWindowId: ((String?) -> Void)?
    var onSelectPack: ((String) -> Void)?
    var onImportCustomPack: ((DeepSeekRolePack) -> Void)?
    var onImportOfficialCSVs: ((OfficialCSVReconciliation) -> Void)?
    var onClearOfficialCSV: (() -> Void)?
    var onConfigureApiKey: (() -> Void)?
    var onFilterChanged: (() -> Void)?
    var onRequestClosePopover: (() -> Void)?
    var onModalPanelStateChange: ((Bool) -> Void)?
    var onQuitApp: (() -> Void)?

    private let brandIconView = NSImageView()
    private let headerSpriteView = NSImageView()
    private let headerStatusLabel = NSTextField(labelWithString: "AgentSpur")
    private let headerSubLabel = NSTextField(labelWithString: "opencode.db · 今日只读")
    private var currencyBtn: NSButton!
    private let quotaInfoLabel = NSTextField(labelWithString: "")

    private let autoFocusSwitch = NSSwitch()
    private let autoFocusPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var popupWindowIds: [String?] = [nil]

    private var groupSegment: NSSegmentedControl!
    private let listStack = NSStackView()
    private var activeRowViews: [SessionRowView] = []
    private var collapsedMasterIds = Set<String>()

    private let billingCard = BillingTelemetryCardView()
    private var csvActionBtn: NSButton!
    private var csvClearBtn: NSButton!

    private let chartMetricSegment = NSSegmentedControl(
        labels: ["请求 次/时", "开销 ¥/时", "缓存 %/时"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let chartView = NativeTodayHourlyChartView()

    private let silentSwitch = NSSwitch()
    private let packPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private var currentFilter: SessionGroupFilter = .all
    private var lastRenderedSnapshot: OpenCodeDBSnapshot?
    private var keyMonitor: Any?

    override func loadView() {
        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 454, height: 702))
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .aqua)

        // 高不透明度冰瓷亮底 (alpha 0.94)，彻底隔绝后方深色终端透色造成的灰暗与文字对比度下降
        let porcelainTint = NSView()
        porcelainTint.wantsLayer = true
        porcelainTint.layer?.backgroundColor = NSColor(srgbRed: 0.968, green: 0.980, blue: 0.994, alpha: 0.94).cgColor
        porcelainTint.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(porcelainTint)
        NSLayoutConstraint.activate([
            porcelainTint.topAnchor.constraint(equalTo: effectView.topAnchor),
            porcelainTint.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            porcelainTint.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            porcelainTint.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])

        self.view = effectView
        setupLayout()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc 关闭卡片
                self?.onRequestClosePopover?()
                return nil
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "r" {
                self?.onRefreshQuota?()
                return nil
            }
            return event
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func setupLayout() {
        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .width
        rootStack.spacing = 7.5
        rootStack.edgeInsets = NSEdgeInsets(top: 11, left: 14, bottom: 11, right: 14)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: view.topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.widthAnchor.constraint(equalToConstant: 454)
        ])

        // 1. Header Row
        brandIconView.image = SpriteRenderer.renderBrandLogoImage(pointSize: 22)
        brandIconView.translatesAutoresizingMaskIntoConstraints = false
        headerSpriteView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            brandIconView.widthAnchor.constraint(equalToConstant: 22),
            brandIconView.heightAnchor.constraint(equalToConstant: 22),
            headerSpriteView.widthAnchor.constraint(equalToConstant: 20),
            headerSpriteView.heightAnchor.constraint(equalToConstant: 20)
        ])

        headerStatusLabel.font = NSFont.systemFont(ofSize: 13.0, weight: .semibold)
        headerStatusLabel.textColor = NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)
        headerStatusLabel.lineBreakMode = .byTruncatingTail
        headerStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        headerSubLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.0, weight: .medium)
        headerSubLabel.textColor = NSColor(srgbRed: 0.32, green: 0.40, blue: 0.50, alpha: 1.0)
        headerSubLabel.lineBreakMode = .byTruncatingTail
        headerSubLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let titleStack = NSStackView(views: [headerStatusLabel, headerSubLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 1
        titleStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        currencyBtn = makeLightButton(title: "¥ CNY", tinted: true, action: #selector(handleCurrencyToggleClick))
        let keyBtn = makeLightButton(title: "额度Key", tinted: false, action: #selector(handleApiKeyClick))
        let refreshBtn = makeLightButton(title: "刷新 ⌘R", tinted: false, action: #selector(handleRefreshClick))

        let topBar = NSStackView(views: [brandIconView, headerSpriteView, titleStack, NSView(), currencyBtn, keyBtn, refreshBtn])
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 5
        rootStack.addArrangedSubview(topBar)

        quotaInfoLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.0, weight: .medium)
        quotaInfoLabel.textColor = NSColor(srgbRed: 0.24, green: 0.32, blue: 0.43, alpha: 1.0)
        quotaInfoLabel.lineBreakMode = .byTruncatingTail
        rootStack.addArrangedSubview(quotaInfoLabel)

        rootStack.addArrangedSubview(makeHairline())

        // 2. 今日精算与 Cache 命中透视卡片
        let billingTitle = NSTextField(labelWithString: "今日开销精算与 Cache 命中透视")
        billingTitle.font = NSFont.systemFont(ofSize: 11.2, weight: .semibold)
        billingTitle.textColor = NSColor(srgbRed: 0.07, green: 0.11, blue: 0.18, alpha: 1.0)

        csvClearBtn = makeLightButton(title: "切回今日库", tinted: false, action: #selector(handleClearCSVClick))
        csvClearBtn.isHidden = true
        csvActionBtn = makeLightButton(title: "导入官方CSV", tinted: true, action: #selector(handleImportCSVClick))

        let billingHeader = NSStackView(views: [billingTitle, NSView(), csvClearBtn, csvActionBtn])
        billingHeader.orientation = .horizontal
        billingHeader.alignment = .centerY
        billingHeader.spacing = 5
        rootStack.addArrangedSubview(billingHeader)

        rootStack.addArrangedSubview(billingCard)

        rootStack.addArrangedSubview(makeHairline())

        // 3. Real Terminal Window Auto-Focus Bar
        autoFocusSwitch.controlSize = .mini
        autoFocusSwitch.target = self
        autoFocusSwitch.action = #selector(handleAutoFocusToggle)

        let autoFocusLabel = NSTextField(labelWithString: "终端自动聚焦")
        autoFocusLabel.font = NSFont.systemFont(ofSize: 11.2, weight: .semibold)
        autoFocusLabel.textColor = NSColor(srgbRed: 0.08, green: 0.13, blue: 0.20, alpha: 1.0)
        autoFocusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        autoFocusPopup.controlSize = .small
        autoFocusPopup.font = NSFont.systemFont(ofSize: 11)
        autoFocusPopup.addItem(withTitle: "自动跟随当前前台终端窗口")
        autoFocusPopup.target = self
        autoFocusPopup.action = #selector(handleAutoFocusTargetChange)
        autoFocusPopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let focusRow = NSStackView(views: [autoFocusSwitch, autoFocusLabel, NSView(), autoFocusPopup])
        focusRow.orientation = .horizontal
        focusRow.alignment = .centerY
        focusRow.spacing = 6
        rootStack.addArrangedSubview(focusRow)

        // 4. Full-Width Session Group Filter
        groupSegment = NSSegmentedControl(
            labels: ["今日 0", "待处理 0", "运行中 0", "已完成 0"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(handleGroupSegmentChange)
        )
        groupSegment.selectedSegment = 0
        groupSegment.segmentStyle = .rounded
        groupSegment.segmentDistribution = .fillEqually
        groupSegment.controlSize = .small
        rootStack.addArrangedSubview(groupSegment)

        // 5. Scrollable Read-Only Session Hierarchy
        listStack.orientation = .vertical
        listStack.alignment = .width
        listStack.spacing = 4.5
        listStack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 192).isActive = true
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)

        let docContainer = FlippedDocumentView()
        docContainer.translatesAutoresizingMaskIntoConstraints = false
        docContainer.addSubview(listStack)
        scrollView.documentView = docContainer

        NSLayoutConstraint.activate([
            docContainer.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            docContainer.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            docContainer.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            listStack.topAnchor.constraint(equalTo: docContainer.topAnchor),
            listStack.leadingAnchor.constraint(equalTo: docContainer.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: docContainer.trailingAnchor),
            listStack.bottomAnchor.constraint(equalTo: docContainer.bottomAnchor)
        ])
        rootStack.addArrangedSubview(scrollView)

        rootStack.addArrangedSubview(makeHairline())

        // 6. Today 24-Hour Interactive Chart Section
        let chartTitle = NSTextField(labelWithString: "今日 24 小时分时趋势 (悬停看明细)")
        chartTitle.font = NSFont.systemFont(ofSize: 11.2, weight: .semibold)
        chartTitle.textColor = NSColor(srgbRed: 0.07, green: 0.11, blue: 0.18, alpha: 1.0)

        chartMetricSegment.selectedSegment = 0
        chartMetricSegment.controlSize = .mini
        chartMetricSegment.target = self
        chartMetricSegment.action = #selector(handleChartMetricChange)

        let chartHeader = NSStackView(views: [chartTitle, NSView(), chartMetricSegment])
        chartHeader.orientation = .horizontal
        chartHeader.alignment = .centerY
        rootStack.addArrangedSubview(chartHeader)

        chartView.translatesAutoresizingMaskIntoConstraints = false
        chartView.heightAnchor.constraint(equalToConstant: 88).isActive = true
        chartView.setContentHuggingPriority(.required, for: .vertical)
        chartView.setContentCompressionResistancePriority(.required, for: .vertical)
        rootStack.addArrangedSubview(chartView)

        rootStack.addArrangedSubview(makeHairline())

        // 7. Preferences & Role Pack Footer
        silentSwitch.controlSize = .mini
        silentSwitch.target = self
        silentSwitch.action = #selector(handleSilentSwitchToggle)

        let silentLabel = NSTextField(labelWithString: "静音通知")
        silentLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        silentLabel.textColor = NSColor(srgbRed: 0.14, green: 0.20, blue: 0.28, alpha: 1.0)
        silentLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        packPopup.controlSize = .small
        packPopup.font = NSFont.systemFont(ofSize: 11)
        packPopup.target = self
        packPopup.action = #selector(handlePackSelection)

        let importBtn = makeLightButton(title: "导入角色包", tinted: true, action: #selector(handleImportPackClick))
        let quitBtn = makeLightButton(title: "退出", tinted: false, action: #selector(handleQuitClick))

        let footerRow = NSStackView(views: [silentSwitch, silentLabel, NSView(), packPopup, importBtn, quitBtn])
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        footerRow.spacing = 6
        rootStack.addArrangedSubview(footerRow)
    }

    // MARK: - Fast 15 FPS Sprite-Only Update & 1 Hz Timer Update (No View Rebuild!)

    func tickAnimationFrame(topState: AgentRunState, activePack: DeepSeekRolePack, frameIndex: Int) {
        guard isViewLoaded else { return }
        headerSpriteView.image = SpriteRenderer.renderSpriteFrame(
            state: topState,
            pack: activePack,
            frame: frameIndex,
            pointSize: 20
        )
        for row in activeRowViews {
            let ptSize: CGFloat = row.isSubTaskRow ? 13 : 16
            row.updateSpriteOnly(
                SpriteRenderer.renderSpriteFrame(
                    state: row.boundState,
                    pack: activePack,
                    frame: frameIndex,
                    pointSize: ptSize
                )
            )
        }
    }

    func tickOneSecondTimers(topState: AgentRunState, topEnteredAtMs: Int64) {
        guard isViewLoaded else { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let topTimer = TimeFormatters.liveStateTimerLabel(
            state: topState,
            enteredAtMs: topEnteredAtMs,
            nowMs: nowMs
        )
        headerStatusLabel.stringValue = "AgentSpur · \(topTimer)"
        for row in activeRowViews {
            row.updateLiveTimerText(nowMs: nowMs)
        }
    }

    // MARK: - Full Data Render

    func renderSnapshot(
        snapshot: OpenCodeDBSnapshot,
        quota: QuotaSnapshot,
        currencyMode: CurrencyDisplayMode,
        csvReconciliation: OfficialCSVReconciliation?,
        activePack: DeepSeekRolePack,
        allPacks: [DeepSeekRolePack],
        frameIndex: Int,
        autoFocusEnabled: Bool,
        selectedWindowId: String?,
        silentAlertEnabled: Bool
    ) {
        guard isViewLoaded else { return }
        self.lastRenderedSnapshot = snapshot
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let currentWindow = DeepSeekPricingEngine.priceWindow()
        let safeRate = max(1.0, quota.usdToCnyRate)

        headerSpriteView.image = SpriteRenderer.renderSpriteFrame(
            state: snapshot.topState,
            pack: activePack,
            frame: frameIndex,
            pointSize: 20
        )

        let topTimer = TimeFormatters.liveStateTimerLabel(
            state: snapshot.topState,
            enteredAtMs: snapshot.topStateEnteredAtMs,
            nowMs: nowMs
        )
        headerStatusLabel.stringValue = "AgentSpur · \(topTimer)"

        let runningMasterCount = snapshot.masters.filter { $0.state.isActiveRunning }.count
        let activeSubCount = snapshot.masters.reduce(0) { acc, m in
            acc + m.subTasks.filter { $0.state.isActiveRunning }.count
        }
        headerSubLabel.stringValue = snapshot.dbExists
            ? "\(snapshot.activeDbFileName) · 今日会话 \(snapshot.masters.count) · 活跃代理 \(runningMasterCount + activeSubCount)"
            : "等待 ~/.local/share/opencode/ 产生会话"

        currencyBtn.title = currencyMode.toggleButtonTitle

        let walletSummary: String
        if let apiBal = quota.apiTotalBalance {
            let balCny = quota.apiCurrency == "USD" ? apiBal * safeRate : apiBal
            let formatted = DeepSeekPricingEngine.formatMoney(
                amountCny: balCny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: false
            )
            walletSummary = "钱包余额 \(formatted) (\(quota.walletBreakdownLabel))"
        } else {
            let formatted = DeepSeekPricingEngine.formatMoney(
                amountCny: snapshot.billing.spurCostCny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: true
            )
            walletSummary = "今日精算 \(formatted)"
        }

        quotaInfoLabel.stringValue = String(
            format: "%@ · Cache %.1f%% · %@(UTC+8) · %@ $1=¥%.4f · %@",
            walletSummary,
            snapshot.billing.cacheHitRatePercent,
            currentWindow.badgeText,
            quota.fxSourceLabel,
            safeRate,
            quota.lastRefreshedHHMM
        )

        csvClearBtn.isHidden = (csvReconciliation == nil)
        billingCard.update(
            billing: snapshot.billing,
            csvReconciliation: csvReconciliation,
            currencyMode: currencyMode,
            usdToCnyRate: safeRate,
            currentWindow: currentWindow
        )

        // 同步本机真实打开的终端窗口列表
        autoFocusSwitch.state = autoFocusEnabled ? .on : .off
        autoFocusPopup.isEnabled = autoFocusEnabled

        var desiredTitles: [String] = ["自动跟随当前前台终端窗口 (\(snapshot.realWindows.count)个在线)"]
        var desiredIds: [String?] = [nil]
        for w in snapshot.realWindows {
            desiredTitles.append(w.popupMenuTitle)
            desiredIds.append(w.id)
        }
        if snapshot.realWindows.isEmpty {
            desiredTitles = ["自动跟随前台终端 (点击任务可唤醒终端)"]
            desiredIds = [nil]
        }

        let currentPopupTitles = autoFocusPopup.itemArray.map { $0.title }
        if currentPopupTitles != desiredTitles {
            autoFocusPopup.removeAllItems()
            for t in desiredTitles {
                autoFocusPopup.menu?.addItem(withTitle: t, action: nil, keyEquivalent: "")
            }
            popupWindowIds = desiredIds
        }

        if let selId = selectedWindowId, let idx = popupWindowIds.firstIndex(of: selId) {
            autoFocusPopup.selectItem(at: idx)
        } else {
            autoFocusPopup.selectItem(at: 0)
        }

        silentSwitch.state = silentAlertEnabled ? .on : .off

        let packTitles = allPacks.map { $0.name }
        if packPopup.itemTitles != packTitles {
            packPopup.removeAllItems()
            packPopup.addItems(withTitles: packTitles)
        }
        if let pIdx = allPacks.firstIndex(where: { $0.id == activePack.id }) {
            packPopup.selectItem(at: pIdx)
        }

        let pending = snapshot.masters.filter { $0.state == .confirm }
        let running = snapshot.masters.filter { $0.state == .thinking || $0.state == .working }
        let completed = snapshot.masters.filter { $0.state == .completed || $0.state == .error }

        groupSegment.setLabel("今日 \(snapshot.masters.count)", forSegment: 0)
        groupSegment.setLabel("待处理 \(pending.count)", forSegment: 1)
        groupSegment.setLabel("运行中 \(running.count)", forSegment: 2)
        groupSegment.setLabel("已完成 \(completed.count)", forSegment: 3)

        for v in listStack.arrangedSubviews {
            listStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        activeRowViews.removeAll()

        let groupsToShow: [(String, [MasterSessionItem])]
        switch currentFilter {
        case .all:
            groupsToShow = [("待处理", pending), ("运行中", running), ("已完成", completed)]
        case .pending:
            groupsToShow = [("待处理", pending)]
        case .running:
            groupsToShow = [("运行中", running)]
        case .completed:
            groupsToShow = [("已完成", completed)]
        }

        for (groupTitle, items) in groupsToShow {
            if currentFilter == .all && items.isEmpty && groupTitle != "运行中" {
                continue
            }
            let gLabel = NSTextField(labelWithString: "  \(groupTitle) (\(items.count))")
            gLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
            gLabel.textColor = NSColor(srgbRed: 0.28, green: 0.36, blue: 0.46, alpha: 1.0)
            listStack.addArrangedSubview(gLabel)

            if items.isEmpty {
                let empty = NSTextField(labelWithString: "    当前无\(groupTitle)任务")
                empty.font = NSFont.systemFont(ofSize: 11)
                empty.textColor = NSColor(srgbRed: 0.42, green: 0.50, blue: 0.59, alpha: 1.0)
                listStack.addArrangedSubview(empty)
                continue
            }

            for m in items {
                let row = SessionRowView(isSubTask: false)
                let mSprite = SpriteRenderer.renderSpriteFrame(
                    state: m.state,
                    pack: activePack,
                    frame: frameIndex,
                    pointSize: 16
                )

                var metaParts: [String] = []
                if m.spurCostCny > 0 {
                    let totalStr = DeepSeekPricingEngine.formatMoney(
                        amountCny: m.spurCostCny,
                        mode: currencyMode,
                        usdToCnyRate: safeRate,
                        highPrecision: true
                    )
                    if !m.subTasks.isEmpty && abs(m.spurCostCny - m.ownCostCny) > 0.0001 {
                        let ownStr = DeepSeekPricingEngine.formatMoney(
                            amountCny: m.ownCostCny,
                            mode: currencyMode,
                            usdToCnyRate: safeRate,
                            highPrecision: m.ownCostCny < 0.1
                        )
                        metaParts.append("总 \(totalStr) (主 \(ownStr))")
                    } else {
                        metaParts.append(totalStr)
                    }
                }
                if (m.inputCacheHitTokens + m.inputCacheMissTokens) > 0 {
                    metaParts.append(String(format: "缓 %.0f%%", m.cacheHitPercent))
                }
                if m.requestCount > 0 {
                    metaParts.append("\(m.requestCount)次")
                }
                if m.state == .completed, let dur = m.completedDurationSec {
                    metaParts.append("耗时\(TimeFormatters.formatCompactSeconds(dur))")
                }
                if metaParts.isEmpty {
                    metaParts.append(m.modelName)
                }

                let mFocused = autoFocusEnabled && shouldHighlightWindow(m.matchedWindow, selectedWindowId: selectedWindowId)
                let isCollapsed = collapsedMasterIds.contains(m.id)

                let mUsd = m.spurCostCny / safeRate
                let winDesc = m.matchedWindow?.popupMenuTitle ?? (m.directory.isEmpty ? "本地会话" : m.directory)
                let mTip = String(
                    format: "点击跳回: %@\n目录: %@\n模型: %@ · 今日请求 %d 次\n含子代理总计: ¥%.4f ($%.4f) · 主会话自身: ¥%.4f (opencode记录 $%.4f)\nCache 命中: %@ / 未命中: %@ (%.1f%% · 已省 ¥%.4f)\n输出+推理: %@ · 状态源: %@",
                    winDesc,
                    m.directory,
                    m.modelName,
                    m.requestCount,
                    m.spurCostCny,
                    mUsd,
                    m.ownCostCny,
                    m.ownOpenCodeUsd,
                    TimeFormatters.formatTokenCount(m.inputCacheHitTokens),
                    TimeFormatters.formatTokenCount(m.inputCacheMissTokens),
                    m.cacheHitPercent,
                    m.cacheSavedCny,
                    TimeFormatters.formatTokenCount(m.outputTokens),
                    m.dbRecordRef
                )

                row.configureMaster(
                    state: m.state,
                    enteredAtMs: m.stateEnteredAtMs,
                    sprite: mSprite,
                    title: m.title,
                    nowMs: nowMs,
                    metaSummaryLeft: metaParts.joined(separator: " · "),
                    terminalBadge: m.consoleBadgeText,
                    subTaskCount: m.subTasks.count,
                    isCollapsed: isCollapsed,
                    isAutoFocused: mFocused,
                    tooltipText: mTip
                )
                row.onClick = { [weak self] in
                    self?.onRequestClosePopover?()
                    TerminalBridge.jumpToRealWindow(m.matchedWindow, fallbackDirectory: m.directory)
                }
                let masterId = m.id
                row.onToggleCollapse = { [weak self] in
                    guard let self else { return }
                    if self.collapsedMasterIds.contains(masterId) {
                        self.collapsedMasterIds.remove(masterId)
                    } else {
                        self.collapsedMasterIds.insert(masterId)
                    }
                    self.onFilterChanged?()
                }
                listStack.addArrangedSubview(row)
                activeRowViews.append(row)

                guard !isCollapsed else { continue }

                for sub in m.subTasks {
                    let subRow = SessionRowView(isSubTask: true)
                    let sSprite = SpriteRenderer.renderSpriteFrame(
                        state: sub.state,
                        pack: activePack,
                        frame: frameIndex,
                        pointSize: 13
                    )
                    let sDur = (sub.state == .completed)
                        ? sub.completedDurationSec.map { "耗时\(TimeFormatters.formatCompactSeconds($0))" }
                        : nil
                    let sCost = sub.spurCostCny > 0
                        ? DeepSeekPricingEngine.formatMoney(amountCny: sub.spurCostCny, mode: currencyMode, usdToCnyRate: safeRate, highPrecision: true)
                        : nil
                    let sCacheBadge = (sub.inputCacheHitTokens + sub.inputCacheMissTokens) > 0
                        ? String(format: "缓%.0f%%", sub.cacheHitPercent)
                        : nil
                    let sFocused = autoFocusEnabled && shouldHighlightWindow(sub.matchedWindow, selectedWindowId: selectedWindowId)
                    let distinctBadge = (sub.consoleBadgeText != m.consoleBadgeText) ? sub.consoleBadgeText : nil

                    // 清理子任务标题中已重复的 (@dev subagent) 后缀，让标题更清爽
                    let cleanSubTitle = sub.title
                        .replacingOccurrences(of: " (\(sub.roleLabel) subagent)", with: "")
                        .replacingOccurrences(of: "(\(sub.roleLabel) subagent)", with: "")

                    let sUsd = sub.spurCostCny / safeRate
                    let sWinDesc = sub.matchedWindow?.popupMenuTitle ?? sub.directory
                    let sTip = String(
                        format: "子任务 %@ · 终端: %@\n今日请求 %d 次 · Cache 命中 %@ (%.1f%% · 已省 ¥%.4f)\n未命中 %@ · 输出 %@ · 今日精算 ¥%.6f ($%.6f)",
                        sub.roleLabel,
                        sWinDesc,
                        sub.requestCount,
                        TimeFormatters.formatTokenCount(sub.inputCacheHitTokens),
                        sub.cacheHitPercent,
                        sub.cacheSavedCny,
                        TimeFormatters.formatTokenCount(sub.inputCacheMissTokens),
                        TimeFormatters.formatTokenCount(sub.outputTokens),
                        sub.spurCostCny,
                        sUsd
                    )

                    subRow.configureSubTask(
                        state: sub.state,
                        enteredAtMs: sub.stateEnteredAtMs,
                        sprite: sSprite,
                        roleLabel: sub.roleLabel,
                        title: cleanSubTitle,
                        nowMs: nowMs,
                        durationSuffix: sDur,
                        costSuffix: sCost,
                        cacheBadgeSuffix: sCacheBadge,
                        distinctTerminalBadge: distinctBadge,
                        isAutoFocused: sFocused,
                        tooltipText: sTip
                    )
                    subRow.onClick = { [weak self] in
                        self?.onRequestClosePopover?()
                        TerminalBridge.jumpToRealWindow(sub.matchedWindow, fallbackDirectory: sub.directory)
                    }
                    listStack.addArrangedSubview(subRow)
                    activeRowViews.append(subRow)
                }
            }
        }

        chartView.points = snapshot.todayHourlySeries
    }

    private func shouldHighlightWindow(_ matched: RealTerminalWindow?, selectedWindowId: String?) -> Bool {
        guard let matched else { return false }
        if let selId = selectedWindowId {
            return matched.id == selId
        }
        return matched.isActiveTab
    }

    // MARK: - Control Actions

    @objc private func handleRefreshClick() {
        onRefreshQuota?()
    }

    @objc private func handleCurrencyToggleClick() {
        onToggleCurrencyMode?()
    }

    @objc private func handleApiKeyClick() {
        onConfigureApiKey?()
    }

    @objc private func handleImportCSVClick() {
        onModalPanelStateChange?(true)
        defer {
            onModalPanelStateChange?(false)
            NSApplication.shared.activate()
        }

        let panel = NSOpenPanel()
        panel.title = "导入 DeepSeek 官方账单 CSV (可同时多选 amount-*.csv 与 cost-*.csv)"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        NSApplication.shared.activate()
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            if let parsed = DeepSeekPricingEngine.parseOfficialCSVFiles(urls: panel.urls) {
                onImportOfficialCSVs?(parsed)
            }
        }
    }

    @objc private func handleClearCSVClick() {
        onClearOfficialCSV?()
    }

    @objc private func handleAutoFocusToggle() {
        onToggleAutoFocus?(autoFocusSwitch.state == .on)
    }

    @objc private func handleAutoFocusTargetChange() {
        let idx = autoFocusPopup.indexOfSelectedItem
        if idx >= 0 && idx < popupWindowIds.count {
            onSelectRealWindowId?(popupWindowIds[idx])
        }
    }

    @objc private func handleGroupSegmentChange() {
        currentFilter = SessionGroupFilter(rawValue: groupSegment.selectedSegment) ?? .all
        onFilterChanged?()
    }

    @objc private func handleChartMetricChange() {
        chartView.metricKind = ChartMetricKind(rawValue: chartMetricSegment.selectedSegment) ?? .requests
    }

    @objc private func handleSilentSwitchToggle() {
        onToggleSilentAlert?(silentSwitch.state == .on)
    }

    @objc private func handlePackSelection() {
        let title = packPopup.titleOfSelectedItem ?? ""
        onSelectPack?(title)
    }

    @objc private func handleImportPackClick() {
        onModalPanelStateChange?(true)
        defer {
            onModalPanelStateChange?(false)
            NSApplication.shared.activate()
        }

        let panel = NSOpenPanel()
        panel.title = "导入自制 DeepSeek 角色包 (.json)"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        NSApplication.shared.activate()
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(DeepSeekRolePack.self, from: data) {
            onImportCustomPack?(decoded)
        }
    }

    @objc private func handleQuitClick() {
        onQuitApp?()
    }

    private func makeHairline() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 0.075).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private func makeLightButton(title: String, tinted: Bool, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .rounded
        btn.controlSize = .small
        btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        btn.setContentCompressionResistancePriority(.required, for: .horizontal)
        btn.setContentHuggingPriority(.required, for: .horizontal)
        if tinted {
            btn.contentTintColor = NSColor(srgbRed: 0.01, green: 0.52, blue: 0.78, alpha: 1.0)
        }
        return btn
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
