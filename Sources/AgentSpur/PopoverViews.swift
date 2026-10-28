import AppKit
import Foundation
import QuartzCore
import UniformTypeIdentifiers

// MARK: - Native macOS Narrow-Border Capsule Button (Uniform 28pt Height · 1:1 Design Parity)

private final class CapsuleControlButton: NSView {
    var onPress: (() -> Void)?

    private let titleField = NSTextField(labelWithString: "")
    private let symbolView = NSImageView()
    private var isHovered = false
    private var trackingRef: NSTrackingArea?
    private let fixedWidth: CGFloat?
    private let usesSymbol: Bool

    var isTintedAccent: Bool = false {
        didSet { updateVisualStyle() }
    }

    var text: String {
        get { titleField.stringValue }
        set {
            titleField.stringValue = newValue
            invalidateIntrinsicContentSize()
        }
    }

    init(
        title: String,
        symbolName: String? = nil,
        fixedWidth: CGFloat? = nil,
        fontSize: CGFloat = 11.2,
        monospaced: Bool = false
    ) {
        self.fixedWidth = fixedWidth
        self.usesSymbol = (symbolName != nil)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1.0

        var constraints: [NSLayoutConstraint] = [
            heightAnchor.constraint(equalToConstant: 28)
        ]

        if let sym = symbolName,
           let img = NSImage(systemSymbolName: sym, accessibilityDescription: title)?
               .withSymbolConfiguration(.init(pointSize: 12.5, weight: .medium)) {
            symbolView.image = img
            symbolView.imageScaling = .scaleProportionallyDown
            symbolView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(symbolView)
            constraints.append(contentsOf: [
                symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
                symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
                symbolView.widthAnchor.constraint(equalToConstant: 15),
                symbolView.heightAnchor.constraint(equalToConstant: 15)
            ])
        } else {
            titleField.stringValue = title
            titleField.font = monospaced
                ? NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
                : NSFont.systemFont(ofSize: fontSize, weight: .medium)
            titleField.alignment = .center
            titleField.lineBreakMode = .byTruncatingTail
            titleField.translatesAutoresizingMaskIntoConstraints = false
            addSubview(titleField)

            let hPad: CGFloat = fixedWidth != nil ? 4 : 10.5
            constraints.append(contentsOf: [
                titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
                titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPad),
                titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPad)
            ])
        }

        if let fw = fixedWidth {
            constraints.append(widthAnchor.constraint(equalToConstant: fw))
        }
        NSLayoutConstraint.activate(constraints)

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        updateVisualStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingRef { removeTrackingArea(t) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingRef = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        return super.hitTest(point) != nil ? self : nil
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateVisualStyle()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateVisualStyle()
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor(srgbRed: 0.90, green: 0.94, blue: 0.98, alpha: 1.0).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        updateVisualStyle()
        if bounds.insetBy(dx: -4, dy: -4).contains(pt) {
            let handler = onPress
            DispatchQueue.main.async {
                handler?()
            }
        }
    }

    private func updateVisualStyle() {
        if isTintedAccent {
            layer?.backgroundColor = isHovered
                ? NSColor(srgbRed: 0.88, green: 0.95, blue: 1.00, alpha: 1.0).cgColor
                : NSColor(srgbRed: 0.93, green: 0.97, blue: 1.00, alpha: 1.0).cgColor
            layer?.borderColor = NSColor(srgbRed: 0.68, green: 0.87, blue: 0.98, alpha: 1.0).cgColor
            let fg = NSColor(srgbRed: 0.01, green: 0.43, blue: 0.66, alpha: 1.0)
            titleField.textColor = fg
            if usesSymbol { symbolView.contentTintColor = fg }
        } else {
            layer?.backgroundColor = isHovered
                ? NSColor(srgbRed: 0.96, green: 0.975, blue: 0.99, alpha: 1.0).cgColor
                : NSColor.white.cgColor
            layer?.borderColor = isHovered
                ? NSColor(srgbRed: 0.74, green: 0.81, blue: 0.89, alpha: 1.0).cgColor
                : NSColor(srgbRed: 0.85, green: 0.89, blue: 0.94, alpha: 1.0).cgColor
            let fg = NSColor(srgbRed: 0.16, green: 0.23, blue: 0.33, alpha: 1.0)
            titleField.textColor = fg
            if usesSymbol { symbolView.contentTintColor = fg }
        }
    }
}

// MARK: - Optically Aligned 28pt Running Status Capsule (e.g. "● 正在工作 33s")

private final class RunningStatusCapsuleView: NSView {
    private let dotView = NSView()
    private let textLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1.0

        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3.25
        dotView.translatesAutoresizingMaskIntoConstraints = false

        textLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .semibold)
        textLabel.lineBreakMode = .byClipping
        textLabel.setContentHuggingPriority(.required, for: .horizontal)
        textLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(dotView)
        addSubview(textLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9.5),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 6.5),
            dotView.heightAnchor.constraint(equalToConstant: 6.5),
            textLabel.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 5.5),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(state: AgentRunState, enteredAtMs: Int64, nowMs: Int64) {
        layer?.backgroundColor = state.pillBackgroundColor.cgColor
        layer?.borderColor = state.pillBorderColor.cgColor
        dotView.layer?.backgroundColor = state.accentColor.cgColor
        textLabel.textColor = state.accentColor

        if state == .completed {
            textLabel.stringValue = "空闲待命"
        } else {
            textLabel.stringValue = TimeFormatters.liveStateTimerLabel(
                state: state,
                enteredAtMs: enteredAtMs,
                nowMs: nowMs
            )
        }
    }
}

// MARK: - Full-Width 4-Column Segmented Filter Bar

private final class SegmentTabButton: NSView {
    var onSelect: (() -> Void)?

    private let labelField = NSTextField(labelWithString: "")
    private var isHovered = false
    private var trackingRef: NSTrackingArea?

    var isSelectedSegment: Bool = false {
        didSet { updateAppearance() }
    }

    var titleText: String {
        get { labelField.stringValue }
        set { labelField.stringValue = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6.5

        labelField.alignment = .center
        labelField.lineBreakMode = .byClipping
        labelField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelField)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            labelField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2)
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingRef { removeTrackingArea(t) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingRef = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        return super.hitTest(point) != nil ? self : nil
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        if !isSelectedSegment {
            layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.72).cgColor
        }
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        updateAppearance()
        if bounds.insetBy(dx: -3, dy: -3).contains(pt) {
            let handler = onSelect
            DispatchQueue.main.async {
                handler?()
            }
        }
    }

    private func updateAppearance() {
        if isSelectedSegment {
            layer?.backgroundColor = NSColor.white.cgColor
            layer?.shadowColor = NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0).cgColor
            layer?.shadowOpacity = 0.07
            layer?.shadowRadius = 2.0
            layer?.shadowOffset = CGSize(width: 0, height: -1)
            labelField.font = NSFont.monospacedDigitSystemFont(ofSize: 11.2, weight: .semibold)
            labelField.textColor = NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)
        } else {
            layer?.backgroundColor = isHovered
                ? NSColor(white: 1.0, alpha: 0.45).cgColor
                : NSColor.clear.cgColor
            layer?.shadowOpacity = 0.0
            labelField.font = NSFont.monospacedDigitSystemFont(ofSize: 11.2, weight: .medium)
            labelField.textColor = isHovered
                ? NSColor(srgbRed: 0.12, green: 0.18, blue: 0.28, alpha: 1.0)
                : NSColor(srgbRed: 0.36, green: 0.43, blue: 0.53, alpha: 1.0)
        }
    }
}

private final class SegmentedFilterBarView: NSView {
    var onSelectIndex: ((Int) -> Void)?

    private var tabs: [SegmentTabButton] = []

    var selectedIndex: Int = 0 {
        didSet {
            for (idx, tab) in tabs.enumerated() {
                tab.isSelectedSegment = (idx == selectedIndex)
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8.5
        layer?.backgroundColor = NSColor(srgbRed: 0.892, green: 0.918, blue: 0.952, alpha: 0.90).cgColor

        let initialTitles = ["全部 0", "待处理 0", "运行中 0", "已完成 0"]
        for (idx, title) in initialTitles.enumerated() {
            let btn = SegmentTabButton(frame: .zero)
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.titleText = title
            btn.isSelectedSegment = (idx == 0)
            let captured = idx
            btn.onSelect = { [weak self] in
                guard let self else { return }
                self.selectedIndex = captured
                self.onSelectIndex?(captured)
            }
            addSubview(btn)
            tabs.append(btn)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            tabs[0].leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            tabs[0].centerYAnchor.constraint(equalTo: centerYAnchor),
            tabs[1].leadingAnchor.constraint(equalTo: tabs[0].trailingAnchor, constant: 4),
            tabs[1].centerYAnchor.constraint(equalTo: centerYAnchor),
            tabs[1].widthAnchor.constraint(equalTo: tabs[0].widthAnchor),
            tabs[2].leadingAnchor.constraint(equalTo: tabs[1].trailingAnchor, constant: 4),
            tabs[2].centerYAnchor.constraint(equalTo: centerYAnchor),
            tabs[2].widthAnchor.constraint(equalTo: tabs[0].widthAnchor),
            tabs[3].leadingAnchor.constraint(equalTo: tabs[2].trailingAnchor, constant: 4),
            tabs[3].trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            tabs[3].centerYAnchor.constraint(equalTo: centerYAnchor),
            tabs[3].widthAnchor.constraint(equalTo: tabs[0].widthAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateLabels(_ labels: [String]) {
        for (idx, text) in labels.prefix(tabs.count).enumerated() {
            tabs[idx].titleText = text
        }
    }
}

// MARK: - Dual-Tone Cache Hit Progress Bar (Sky Blue Hit vs Neutral Grey Miss)

private final class DualToneCacheTrackView: NSView {
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

        ctx.setFillColor(NSColor(srgbRed: 0.89, green: 0.92, blue: 0.96, alpha: 1.0).cgColor)
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
                NSColor(srgbRed: 0.14, green: 0.70, blue: 0.95, alpha: 1.0).cgColor
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

// MARK: - Symmetrically Centered Custom Dark Floating Breakdown Hover Card

private final class BreakdownKeyValueRowView: NSView {
    private let keyField = NSTextField(labelWithString: "")
    private let valField = NSTextField(labelWithString: "")

    init(key: String, value: String, valueColor: NSColor) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        keyField.stringValue = key
        keyField.font = NSFont.systemFont(ofSize: 10.8, weight: .regular)
        keyField.textColor = NSColor(srgbRed: 0.62, green: 0.69, blue: 0.79, alpha: 1.0)
        keyField.setContentHuggingPriority(.required, for: .horizontal)
        keyField.setContentCompressionResistancePriority(.required, for: .horizontal)
        keyField.translatesAutoresizingMaskIntoConstraints = false

        valField.stringValue = value
        valField.font = NSFont.monospacedDigitSystemFont(ofSize: 10.8, weight: .medium)
        valField.textColor = valueColor
        valField.alignment = .right
        valField.lineBreakMode = .byTruncatingMiddle
        valField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        valField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(keyField)
        addSubview(valField)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 17.5),
            keyField.leadingAnchor.constraint(equalTo: leadingAnchor),
            keyField.centerYAnchor.constraint(equalTo: centerYAnchor),
            valField.trailingAnchor.constraint(equalTo: trailingAnchor),
            valField.centerYAnchor.constraint(equalTo: centerYAnchor),
            valField.leadingAnchor.constraint(greaterThanOrEqualTo: keyField.trailingAnchor, constant: 10)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class CostBreakdownHoverCardView: NSView {
    private let headerTitleLabel = NSTextField(labelWithString: "")
    private let headerRightLabel = NSTextField(labelWithString: "")
    private let rowsContainer = NSView()
    private var rowConstraints: [NSLayoutConstraint] = []

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor(srgbRed: 0.059, green: 0.090, blue: 0.165, alpha: 0.97).cgColor
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor(srgbRed: 0.22, green: 0.30, blue: 0.42, alpha: 0.85).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.26
        layer?.shadowRadius = 15
        layer?.shadowOffset = CGSize(width: 0, height: -6)

        headerTitleLabel.font = NSFont.systemFont(ofSize: 11.4, weight: .semibold)
        headerTitleLabel.textColor = NSColor(srgbRed: 0.49, green: 0.83, blue: 0.99, alpha: 1.0)
        headerTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        headerRightLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.4, weight: .medium)
        headerRightLabel.textColor = NSColor(srgbRed: 0.60, green: 0.67, blue: 0.77, alpha: 1.0)
        headerRightLabel.alignment = .right
        headerRightLabel.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.10).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false

        rowsContainer.translatesAutoresizingMaskIntoConstraints = false

        addSubview(headerTitleLabel)
        addSubview(headerRightLabel)
        addSubview(divider)
        addSubview(rowsContainer)

        NSLayoutConstraint.activate([
            headerTitleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            headerTitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            headerRightLabel.centerYAnchor.constraint(equalTo: headerTitleLabel.centerYAnchor),
            headerRightLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            headerRightLabel.leadingAnchor.constraint(greaterThanOrEqualTo: headerTitleLabel.trailingAnchor, constant: 8),

            divider.topAnchor.constraint(equalTo: headerTitleLabel.bottomAnchor, constant: 7.5),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            divider.heightAnchor.constraint(equalToConstant: 1),

            rowsContainer.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 7.5),
            rowsContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            rowsContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            rowsContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setRows(_ rows: [BreakdownKeyValueRowView]) {
        NSLayoutConstraint.deactivate(rowConstraints)
        rowConstraints.removeAll()
        for v in rowsContainer.subviews {
            v.removeFromSuperview()
        }
        var prev: NSView? = nil
        for (idx, row) in rows.enumerated() {
            rowsContainer.addSubview(row)
            rowConstraints.append(row.leadingAnchor.constraint(equalTo: rowsContainer.leadingAnchor))
            rowConstraints.append(row.trailingAnchor.constraint(equalTo: rowsContainer.trailingAnchor))
            if let p = prev {
                rowConstraints.append(row.topAnchor.constraint(equalTo: p.bottomAnchor, constant: 4.5))
            } else {
                rowConstraints.append(row.topAnchor.constraint(equalTo: rowsContainer.topAnchor))
            }
            if idx == rows.count - 1 {
                rowConstraints.append(row.bottomAnchor.constraint(equalTo: rowsContainer.bottomAnchor))
            }
            prev = row
        }
        NSLayoutConstraint.activate(rowConstraints)
    }

    func configure(
        billing: BillingTelemetrySummary,
        csvReconciliation: OfficialCSVReconciliation?,
        quota: QuotaSnapshot
    ) {
        let safeRate = max(1.0, quota.usdToCnyRate)
        let whiteVal = NSColor(srgbRed: 0.95, green: 0.97, blue: 0.99, alpha: 1.0)
        let emeraldVal = NSColor(srgbRed: 0.32, green: 0.86, blue: 0.64, alpha: 1.0)
        let skyVal = NSColor(srgbRed: 0.49, green: 0.83, blue: 0.99, alpha: 1.0)
        let mutedVal = NSColor(srgbRed: 0.64, green: 0.71, blue: 0.80, alpha: 1.0)

        if let csv = csvReconciliation {
            headerTitleLabel.stringValue = "官方 CSV 账单对账明细"
            headerRightLabel.stringValue = "\(csv.modelName) · $1 = ¥\(String(format: "%.4f", safeRate))"

            let hitPct = csv.cacheHitRatePercent
            setRows([
                BreakdownKeyValueRowView(
                    key: "缓存命中 (Hit)",
                    value: "\(TimeFormatters.formatTokenCount(csv.inputCacheHitTokens)) (\(String(format: "%.1f%%", hitPct))) · 已省 ¥\(String(format: "%.2f", csv.estimatedCacheSavedCny))",
                    valueColor: emeraldVal
                ),
                BreakdownKeyValueRowView(
                    key: "未命中输入 (Miss)",
                    value: TimeFormatters.formatTokenCount(csv.inputCacheMissTokens),
                    valueColor: whiteVal
                ),
                BreakdownKeyValueRowView(
                    key: "输出 + 思维链",
                    value: TimeFormatters.formatTokenCount(csv.outputTokens),
                    valueColor: whiteVal
                ),
                BreakdownKeyValueRowView(
                    key: "对比本地库精算",
                    value: String(format: "¥%.4f · 钱包 %@ (%@)", billing.spurCostCny, csv.walletType, csv.currency),
                    valueColor: mutedVal
                )
            ])
            return
        }

        let shortModel = billing.dominantModelSpec.components(separatedBy: " · ").first ?? "V4.1-Flash"
        headerTitleLabel.stringValue = "\(billing.dateLabel) 精算透视明细"
        headerRightLabel.stringValue = "\(shortModel) · $1 = ¥\(String(format: "%.4f", safeRate))"

        let hitPct = billing.cacheHitRatePercent
        var rows: [BreakdownKeyValueRowView] = [
            BreakdownKeyValueRowView(
                key: "缓存命中 (Hit)",
                value: String(
                    format: "%@ (%.1f%%) · 实付 ¥%.2f · 已省 ¥%.2f",
                    TimeFormatters.formatTokenCount(billing.inputCacheHitTokens),
                    hitPct,
                    billing.cacheHitCostCny,
                    billing.cacheSavedCny
                ),
                valueColor: emeraldVal
            ),
            BreakdownKeyValueRowView(
                key: "未命中输入 (Miss)",
                value: String(
                    format: "%@ (%.1f%%) · 实付 ¥%.2f",
                    TimeFormatters.formatTokenCount(billing.inputCacheMissTokens),
                    billing.cacheMissRatePercent,
                    billing.cacheMissCostCny
                ),
                valueColor: whiteVal
            ),
            BreakdownKeyValueRowView(
                key: "输出 + 思维链",
                value: String(
                    format: "%@ (思维链 %@) · 实付 ¥%.2f",
                    TimeFormatters.formatTokenCount(billing.outputTokens),
                    TimeFormatters.formatTokenCount(billing.reasoningTokens),
                    billing.outputCostCny
                ),
                valueColor: whiteVal
            ),
            BreakdownKeyValueRowView(
                key: "忙闲时段拆分",
                value: String(
                    format: "忙时 ¥%.2f (%d次) · 闲时5折 ¥%.2f (%d次)",
                    billing.peakCostCny,
                    billing.peakRequestCount,
                    billing.offPeakCostCny,
                    billing.offPeakRequestCount
                ),
                valueColor: whiteVal
            ),
            BreakdownKeyValueRowView(
                key: "OpenCode 静态估",
                value: String(format: "$%.4f (未计忙闲时差异)", billing.opencodeRawUsd),
                valueColor: mutedVal
            )
        ]

        if let bal = quota.apiTotalBalance {
            let balSymbol = quota.apiCurrency == "USD" ? "$" : "¥"
            let src = quota.balanceSourceLabel.isEmpty ? "官方实时接口" : quota.balanceSourceLabel
            rows.append(BreakdownKeyValueRowView(
                key: "官方实时余额",
                value: String(format: "%@%.2f · %@", balSymbol, bal, src),
                valueColor: skyVal
            ))
        }
        setRows(rows)
    }
}

// MARK: - Minimalist Cost & Cache Overview Card (Symmetrical Pure Auto Layout)

final class BillingTelemetryCardView: NSView {
    var onExitCSVMode: (() -> Void)?
    var onHoverStateChange: ((Bool) -> Void)?
    var onClickBalanceArea: (() -> Void)?

    private let captionLabel = NSTextField(labelWithString: "今日总开销")
    private let exitCSVChip = CapsuleControlButton(title: "退出对账", fontSize: 10.0)
    private let rightWindowLabel = NSTextField(labelWithString: "")

    private let heroAmountLabel = NSTextField(labelWithString: "¥0.00")
    private let heroSubCurrencyLabel = NSTextField(labelWithString: "≈ $0.00")
    private let savingsInlineLabel = NSTextField(labelWithString: "")

    private let cacheRateLabel = NSTextField(labelWithString: "Cache 命中率 0.0%")
    private let requestMetaLabel = NSTextField(labelWithString: "")
    private let cacheTrack = DualToneCacheTrackView()
    private var trackingRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor(srgbRed: 0.87, green: 0.91, blue: 0.95, alpha: 1.0).cgColor

        captionLabel.font = NSFont.systemFont(ofSize: 11.2, weight: .medium)
        captionLabel.textColor = NSColor(srgbRed: 0.39, green: 0.45, blue: 0.55, alpha: 1.0)
        captionLabel.lineBreakMode = .byTruncatingTail
        captionLabel.translatesAutoresizingMaskIntoConstraints = false

        exitCSVChip.isHidden = true
        exitCSVChip.translatesAutoresizingMaskIntoConstraints = false
        exitCSVChip.onPress = { [weak self] in
            self?.onExitCSVMode?()
        }

        rightWindowLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.6, weight: .medium)
        rightWindowLabel.textColor = NSColor(srgbRed: 0.45, green: 0.52, blue: 0.62, alpha: 1.0)
        rightWindowLabel.alignment = .right
        rightWindowLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        rightWindowLabel.translatesAutoresizingMaskIntoConstraints = false

        heroAmountLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 26.0, weight: .bold)
        heroAmountLabel.textColor = NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)
        heroAmountLabel.translatesAutoresizingMaskIntoConstraints = false

        heroSubCurrencyLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
        heroSubCurrencyLabel.textColor = NSColor(srgbRed: 0.52, green: 0.59, blue: 0.68, alpha: 1.0)
        heroSubCurrencyLabel.translatesAutoresizingMaskIntoConstraints = false

        savingsInlineLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.2, weight: .semibold)
        savingsInlineLabel.textColor = NSColor(srgbRed: 0.04, green: 0.58, blue: 0.40, alpha: 1.0)
        savingsInlineLabel.alignment = .right
        savingsInlineLabel.translatesAutoresizingMaskIntoConstraints = false

        cacheRateLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .semibold)
        cacheRateLabel.textColor = NSColor(srgbRed: 0.02, green: 0.46, blue: 0.70, alpha: 1.0)
        cacheRateLabel.translatesAutoresizingMaskIntoConstraints = false

        requestMetaLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.6, weight: .regular)
        requestMetaLabel.textColor = NSColor(srgbRed: 0.54, green: 0.61, blue: 0.70, alpha: 1.0)
        requestMetaLabel.alignment = .right
        requestMetaLabel.translatesAutoresizingMaskIntoConstraints = false

        cacheTrack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(captionLabel)
        addSubview(exitCSVChip)
        addSubview(rightWindowLabel)
        addSubview(heroAmountLabel)
        addSubview(heroSubCurrencyLabel)
        addSubview(savingsInlineLabel)
        addSubview(cacheRateLabel)
        addSubview(requestMetaLabel)
        addSubview(cacheTrack)

        NSLayoutConstraint.activate([
            captionLabel.topAnchor.constraint(equalTo: topAnchor, constant: 13.5),
            captionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            exitCSVChip.leadingAnchor.constraint(equalTo: captionLabel.trailingAnchor, constant: 6),
            exitCSVChip.centerYAnchor.constraint(equalTo: captionLabel.centerYAnchor),
            rightWindowLabel.centerYAnchor.constraint(equalTo: captionLabel.centerYAnchor),
            rightWindowLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            rightWindowLabel.leadingAnchor.constraint(greaterThanOrEqualTo: captionLabel.trailingAnchor, constant: 8),

            heroAmountLabel.topAnchor.constraint(equalTo: captionLabel.bottomAnchor, constant: 7.5),
            heroAmountLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            heroSubCurrencyLabel.leadingAnchor.constraint(equalTo: heroAmountLabel.trailingAnchor, constant: 6.5),
            heroSubCurrencyLabel.lastBaselineAnchor.constraint(equalTo: heroAmountLabel.lastBaselineAnchor),
            savingsInlineLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            savingsInlineLabel.lastBaselineAnchor.constraint(equalTo: heroAmountLabel.lastBaselineAnchor),
            savingsInlineLabel.leadingAnchor.constraint(greaterThanOrEqualTo: heroSubCurrencyLabel.trailingAnchor, constant: 8),

            cacheRateLabel.topAnchor.constraint(equalTo: heroAmountLabel.bottomAnchor, constant: 8),
            cacheRateLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            requestMetaLabel.centerYAnchor.constraint(equalTo: cacheRateLabel.centerYAnchor),
            requestMetaLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            requestMetaLabel.leadingAnchor.constraint(greaterThanOrEqualTo: cacheRateLabel.trailingAnchor, constant: 8),

            cacheTrack.topAnchor.constraint(equalTo: cacheRateLabel.bottomAnchor, constant: 5.5),
            cacheTrack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            cacheTrack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            cacheTrack.heightAnchor.constraint(equalToConstant: 7.0),
            cacheTrack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13.5)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingRef { removeTrackingArea(t) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingRef = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        guard super.hitTest(point) != nil else { return nil }
        if !exitCSVChip.isHidden {
            let localPt = superview != nil ? convert(point, from: superview) : point
            if exitCSVChip.frame.insetBy(dx: -3, dy: -3).contains(localPt) {
                return exitCSVChip
            }
        }
        return self
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.borderColor = NSColor(srgbRed: 0.74, green: 0.81, blue: 0.90, alpha: 1.0).cgColor
        onHoverStateChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        layer?.borderColor = NSColor(srgbRed: 0.87, green: 0.91, blue: 0.95, alpha: 1.0).cgColor
        onHoverStateChange?(false)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if rightWindowLabel.frame.insetBy(dx: -12, dy: -8).contains(pt) {
            let handler = onClickBalanceArea
            DispatchQueue.main.async {
                handler?()
            }
        }
    }

    func update(
        scopeTitle: String,
        billing: BillingTelemetrySummary,
        csvReconciliation: OfficialCSVReconciliation?,
        quota: QuotaSnapshot,
        currencyMode: CurrencyDisplayMode,
        currentWindow: BeijingPriceWindow
    ) {
        self.toolTip = nil
        let safeRate = max(1.0, quota.usdToCnyRate)

        if let csv = csvReconciliation {
            exitCSVChip.isHidden = false
            let costCny = csv.currency == "USD" ? csv.totalCostInOriginalCurrency * safeRate : csv.totalCostInOriginalCurrency

            captionLabel.stringValue = "官方 CSV 对账 · \(csv.apiKeyName)"
            rightWindowLabel.stringValue = csv.timeRangeLabel

            heroAmountLabel.stringValue = DeepSeekPricingEngine.formatMoney(
                amountCny: costCny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: costCny > 0 && costCny < 0.1
            )
            heroSubCurrencyLabel.stringValue = "≈ " + DeepSeekPricingEngine.formatMoney(
                amountCny: costCny,
                mode: currencyMode.next,
                usdToCnyRate: safeRate,
                highPrecision: false
            )

            let savedText = DeepSeekPricingEngine.formatMoney(
                amountCny: csv.estimatedCacheSavedCny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: false
            )
            savingsInlineLabel.stringValue = csv.estimatedCacheSavedCny >= 0.01 ? "已省 \(savedText)" : ""

            let hitPct = csv.cacheHitRatePercent
            cacheRateLabel.stringValue = String(format: "Cache 命中率 %.1f%%", hitPct)
            requestMetaLabel.stringValue = "\(TimeFormatters.formatIntWithCommas(csv.requestCount)) 次 · 悬停看明细"
            cacheTrack.hasTraffic = csv.totalInputTokens > 0
            cacheTrack.hitRatio = hitPct / 100.0
            return
        }

        exitCSVChip.isHidden = true
        captionLabel.stringValue = scopeTitle == "全部 Key"
            ? "\(billing.dateLabel) 总开销"
            : "\(billing.dateLabel) · \(scopeTitle)"

        if let bal = quota.apiTotalBalance {
            let balCny = quota.apiCurrency == "USD" ? bal * safeRate : bal
            let balStr = DeepSeekPricingEngine.formatMoney(
                amountCny: balCny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: false
            )
            rightWindowLabel.stringValue = "余额 \(balStr) · \(currentWindow.badgeText)"
        } else {
            rightWindowLabel.stringValue = currentWindow.badgeText
        }

        heroAmountLabel.stringValue = DeepSeekPricingEngine.formatMoney(
            amountCny: billing.spurCostCny,
            mode: currencyMode,
            usdToCnyRate: safeRate,
            highPrecision: billing.spurCostCny > 0 && billing.spurCostCny < 0.1
        )
        heroSubCurrencyLabel.stringValue = "≈ " + DeepSeekPricingEngine.formatMoney(
            amountCny: billing.spurCostCny,
            mode: currencyMode.next,
            usdToCnyRate: safeRate,
            highPrecision: billing.spurCostCny > 0 && billing.spurCostCny < 0.1
        )

        let totalSavedCny = billing.cacheSavedCny + billing.offPeakSavedCny
        if totalSavedCny >= 0.01 {
            let savedStr = DeepSeekPricingEngine.formatMoney(
                amountCny: totalSavedCny,
                mode: currencyMode,
                usdToCnyRate: safeRate,
                highPrecision: false
            )
            savingsInlineLabel.stringValue = "已省 \(savedStr)"
        } else {
            savingsInlineLabel.stringValue = ""
        }

        let hitPct = billing.cacheHitRatePercent
        cacheRateLabel.stringValue = String(format: "Cache 命中率 %.1f%%", hitPct)
        requestMetaLabel.stringValue = billing.requestCount > 0
            ? "\(TimeFormatters.formatIntWithCommas(billing.requestCount)) 次 · 悬停看明细"
            : "今日暂无调用"
        cacheTrack.hasTraffic = billing.totalInputTokens > 0
        cacheTrack.hitRatio = hitPct / 100.0
    }
}

// MARK: - Minimalist 24-Bar Sparkline Chart (Zero Axes · Peak Subtle Tint · Hover Pill)

final class SparklineBarChartView: NSView {
    var points: [TodayHourlyPoint] = [] {
        didSet {
            if points != oldValue {
                needsDisplay = true
            }
        }
    }
    var currencyMode: CurrencyDisplayMode = .cny {
        didSet {
            if currencyMode != oldValue {
                needsDisplay = true
            }
        }
    }
    var usdToCnyRate: Double = 7.12 {
        didSet {
            if abs(usdToCnyRate - oldValue) > 0.0001 {
                needsDisplay = true
            }
        }
    }
    var onHoverReadoutChange: ((String?) -> Void)?

    private var hoveredHour: Int? {
        didSet {
            if hoveredHour != oldValue {
                needsDisplay = true
                if let h = hoveredHour, h >= 0, h < points.count {
                    let pt = points[h]
                    let costStr = DeepSeekPricingEngine.formatMoney(
                        amountCny: pt.costCny,
                        mode: currencyMode,
                        usdToCnyRate: max(1.0, usdToCnyRate),
                        highPrecision: pt.costCny > 0 && pt.costCny < 0.1
                    )
                    let nextH = (pt.hour + 1) % 24
                    onHoverReadoutChange?(String(
                        format: "%02d:00-%02d:00: %d次 | %@",
                        pt.hour,
                        nextH,
                        pt.requestCount,
                        costStr
                    ))
                } else {
                    onHoverReadoutChange?(nil)
                }
            }
        }
    }
    private var trackingRef: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingRef = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard points.count == 24 else { return }
        let pt = convert(event.locationInWindow, from: nil)
        let hPad: CGFloat = 10
        let plotW = max(48, bounds.width - hPad * 2)
        guard pt.x >= hPad - 4, pt.x <= bounds.width - hPad + 4 else {
            hoveredHour = nil
            return
        }
        let slotW = plotW / 24.0
        let rawIdx = Int(((pt.x - hPad) / slotW).rounded(.down))
        hoveredHour = max(0, min(23, rawIdx))
    }

    override func mouseExited(with event: NSEvent) {
        hoveredHour = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let b = bounds
        let bgPath = CGPath(roundedRect: b, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.addPath(bgPath)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()

        ctx.addPath(bgPath)
        ctx.setStrokeColor(NSColor(srgbRed: 0.87, green: 0.91, blue: 0.95, alpha: 1.0).cgColor)
        ctx.setLineWidth(1.0)
        ctx.strokePath()

        guard points.count == 24 else { return }

        let hPad: CGFloat = 10
        let vPadBottom: CGFloat = 7
        let vPadTop: CGFloat = 9
        let plotW = max(48, b.width - hPad * 2)
        let plotH = max(20, b.height - vPadBottom - vPadTop)
        let slotW = plotW / 24.0
        let barW = max(4.0, slotW - 4.2)

        ctx.saveGState()
        ctx.setFillColor(NSColor(srgbRed: 0.96, green: 0.62, blue: 0.07, alpha: 0.045).cgColor)
        for (idx, pt) in points.enumerated() where pt.isPeakHour {
            let sx = hPad + CGFloat(idx) * slotW
            ctx.fill(CGRect(x: sx, y: 3, width: slotW, height: b.height - 6))
        }
        ctx.restoreGState()

        let maxReq = max(1, points.map { $0.requestCount }.max() ?? 1)

        for (idx, pt) in points.enumerated() {
            let sx = hPad + CGFloat(idx) * slotW
            let bx = sx + (slotW - barW) * 0.5
            let isHovered = (hoveredHour == idx)

            let barH: CGFloat
            if pt.requestCount > 0 {
                let ratio = CGFloat(pt.requestCount) / CGFloat(maxReq)
                barH = max(4.5, ratio * plotH)
            } else {
                barH = 2.0
            }

            let barRect = CGRect(x: bx, y: vPadBottom, width: barW, height: barH)
            let barPath = CGPath(roundedRect: barRect, cornerWidth: 2.2, cornerHeight: 2.2, transform: nil)
            ctx.addPath(barPath)

            if isHovered {
                ctx.setFillColor(NSColor(srgbRed: 0.01, green: 0.41, blue: 0.63, alpha: 1.0).cgColor)
            } else if pt.requestCount == 0 {
                ctx.setFillColor(NSColor(srgbRed: 0.89, green: 0.92, blue: 0.96, alpha: 1.0).cgColor)
            } else if pt.isCurrentHour {
                ctx.setFillColor(NSColor(srgbRed: 0.01, green: 0.52, blue: 0.78, alpha: 1.0).cgColor)
            } else if pt.isPeakHour {
                ctx.setFillColor(NSColor(srgbRed: 0.14, green: 0.65, blue: 0.91, alpha: 0.85).cgColor)
            } else {
                ctx.setFillColor(NSColor(srgbRed: 0.34, green: 0.76, blue: 0.96, alpha: 0.78).cgColor)
            }
            ctx.fillPath()
        }

        if let hIdx = hoveredHour, hIdx >= 0, hIdx < points.count {
            let pt = points[hIdx]
            let nextH = (pt.hour + 1) % 24
            let costStr = DeepSeekPricingEngine.formatMoney(
                amountCny: pt.costCny,
                mode: currencyMode,
                usdToCnyRate: max(1.0, usdToCnyRate),
                highPrecision: pt.costCny > 0 && pt.costCny < 0.1
            )
            let tipText = String(format: "%02d:00-%02d:00: %d次 | %@", pt.hour, nextH, pt.requestCount, costStr)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9.8, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let nsTip = NSString(string: tipText)
            let sz = nsTip.size(withAttributes: attrs)
            let pillW = sz.width + 12
            let pillH = sz.height + 5
            let centerBarX = hPad + (CGFloat(hIdx) + 0.5) * slotW
            let pillX = min(max(6, centerBarX - pillW * 0.5), b.width - pillW - 6)
            let pillY = b.height - pillH - 4

            let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)
            let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
            ctx.addPath(pillPath)
            ctx.setFillColor(NSColor(srgbRed: 0.08, green: 0.12, blue: 0.20, alpha: 0.92).cgColor)
            ctx.fillPath()

            nsTip.draw(at: CGPoint(x: pillX + 6, y: pillY + 2.5), withAttributes: attrs)
        }
    }
}

// MARK: - Sub-Agent Count Chip & Minimalist Single-Line Session Row (1:1 Design Parity)

private final class SubCountChipControl: NSView {
    var onTap: (() -> Void)?

    private let labelField = NSTextField(labelWithString: "")
    private var isHovered = false
    private var trackingRef: NSTrackingArea?

    var text: String {
        get { labelField.stringValue }
        set { labelField.stringValue = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4.5

        labelField.font = NSFont.monospacedDigitSystemFont(ofSize: 10.2, weight: .semibold)
        labelField.alignment = .center
        labelField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelField)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 19),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5.5),
            labelField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5.5)
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        updateStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingRef { removeTrackingArea(t) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingRef = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        return super.hitTest(point) != nil ? self : nil
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateStyle()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateStyle()
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor(srgbRed: 0.85, green: 0.89, blue: 0.94, alpha: 1.0).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        updateStyle()
        if bounds.insetBy(dx: -3, dy: -3).contains(pt), let action = onTap {
            DispatchQueue.main.async {
                action()
            }
        }
    }

    private func updateStyle() {
        layer?.backgroundColor = isHovered
            ? NSColor(srgbRed: 0.89, green: 0.92, blue: 0.96, alpha: 1.0).cgColor
            : NSColor(srgbRed: 0.945, green: 0.960, blue: 0.980, alpha: 1.0).cgColor
        labelField.textColor = isHovered
            ? NSColor(srgbRed: 0.12, green: 0.18, blue: 0.28, alpha: 1.0)
            : NSColor(srgbRed: 0.39, green: 0.46, blue: 0.56, alpha: 1.0)
    }
}

final class SessionRowView: NSView {
    var onClick: (() -> Void)?
    var onToggleExpand: (() -> Void)?

    private(set) var boundState: AgentRunState = .completed
    private(set) var boundEnteredAtMs: Int64 = 0
    private(set) var isSubTaskRow = false

    private var isHovered = false
    private var currentIsAutoFocused = false
    private var trackingRef: NSTrackingArea?

    private let iconView = RetinaAspectFitImageView(pointSize: 18)
    private let roleBadgeField = NSTextField(labelWithString: "")
    private let titleField = NSTextField(labelWithString: "")
    private var expandChip: SubCountChipControl?
    private let costField = NSTextField(labelWithString: "")
    private let timerField = NSTextField(labelWithString: "")
    private let goBadgeField = NSTextField(labelWithString: "↗")

    init(isSubTask: Bool) {
        self.isSubTaskRow = isSubTask
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor.clear.cgColor

        titleField.lineBreakMode = .byTruncatingTail
        titleField.usesSingleLineMode = true
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        if isSubTask {
            let treePrefix = NSTextField(labelWithString: "└─")
            treePrefix.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
            treePrefix.textColor = NSColor(srgbRed: 0.72, green: 0.78, blue: 0.85, alpha: 1.0)
            treePrefix.translatesAutoresizingMaskIntoConstraints = false
            treePrefix.setContentHuggingPriority(.required, for: .horizontal)
            treePrefix.setContentCompressionResistancePriority(.required, for: .horizontal)

            roleBadgeField.font = NSFont.monospacedSystemFont(ofSize: 10.2, weight: .semibold)
            roleBadgeField.textColor = NSColor(srgbRed: 0.02, green: 0.45, blue: 0.68, alpha: 1.0)
            roleBadgeField.translatesAutoresizingMaskIntoConstraints = false
            roleBadgeField.setContentHuggingPriority(.required, for: .horizontal)
            roleBadgeField.setContentCompressionResistancePriority(.required, for: .horizontal)

            costField.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
            costField.textColor = NSColor(srgbRed: 0.52, green: 0.59, blue: 0.68, alpha: 1.0)
            costField.alignment = .right
            costField.translatesAutoresizingMaskIntoConstraints = false
            costField.setContentHuggingPriority(.required, for: .horizontal)
            costField.setContentCompressionResistancePriority(.required, for: .horizontal)

            addSubview(treePrefix)
            addSubview(roleBadgeField)
            addSubview(titleField)
            addSubview(costField)

            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: 26),
                treePrefix.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 26),
                treePrefix.centerYAnchor.constraint(equalTo: centerYAnchor),

                roleBadgeField.leadingAnchor.constraint(equalTo: treePrefix.trailingAnchor, constant: 5),
                roleBadgeField.centerYAnchor.constraint(equalTo: centerYAnchor),

                titleField.leadingAnchor.constraint(equalTo: roleBadgeField.trailingAnchor, constant: 5),
                titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
                titleField.trailingAnchor.constraint(lessThanOrEqualTo: costField.leadingAnchor, constant: -8),

                costField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                costField.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        } else {
            let chip = SubCountChipControl(frame: .zero)
            chip.isHidden = true
            chip.translatesAutoresizingMaskIntoConstraints = false
            chip.onTap = { [weak self] in
                self?.onToggleExpand?()
            }
            self.expandChip = chip

            costField.font = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .medium)
            costField.textColor = NSColor(srgbRed: 0.39, green: 0.46, blue: 0.56, alpha: 1.0)
            costField.alignment = .right
            costField.translatesAutoresizingMaskIntoConstraints = false
            costField.setContentHuggingPriority(.required, for: .horizontal)
            costField.setContentCompressionResistancePriority(.required, for: .horizontal)

            timerField.font = NSFont.monospacedDigitSystemFont(ofSize: 10.8, weight: .semibold)
            timerField.alignment = .right
            timerField.translatesAutoresizingMaskIntoConstraints = false
            timerField.setContentHuggingPriority(.required, for: .horizontal)
            timerField.setContentCompressionResistancePriority(.required, for: .horizontal)

            goBadgeField.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
            goBadgeField.textColor = NSColor(srgbRed: 0.72, green: 0.78, blue: 0.85, alpha: 1.0)
            goBadgeField.translatesAutoresizingMaskIntoConstraints = false
            goBadgeField.setContentHuggingPriority(.required, for: .horizontal)
            goBadgeField.setContentCompressionResistancePriority(.required, for: .horizontal)

            let leftRow = NSStackView(views: [iconView, titleField, chip])
            leftRow.orientation = .horizontal
            leftRow.alignment = .centerY
            leftRow.spacing = 7
            leftRow.translatesAutoresizingMaskIntoConstraints = false

            let rightRow = NSStackView(views: [costField, timerField, goBadgeField])
            rightRow.orientation = .horizontal
            rightRow.alignment = .centerY
            rightRow.spacing = 7
            rightRow.translatesAutoresizingMaskIntoConstraints = false
            rightRow.setContentHuggingPriority(.required, for: .horizontal)
            rightRow.setContentCompressionResistancePriority(.required, for: .horizontal)

            addSubview(leftRow)
            addSubview(rightRow)

            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: 34),
                timerField.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),

                leftRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                leftRow.centerYAnchor.constraint(equalTo: centerYAnchor),
                leftRow.trailingAnchor.constraint(lessThanOrEqualTo: rightRow.leadingAnchor, constant: -10),

                rightRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                rightRow.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingRef { removeTrackingArea(t) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applySurfaceAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applySurfaceAppearance()
    }

    func configureMaster(
        state: AgentRunState,
        enteredAtMs: Int64,
        sprite: NSImage,
        title: String,
        costText: String,
        nowMs: Int64,
        subTaskCount: Int,
        isExpanded: Bool,
        isAutoFocused: Bool,
        dimmedCompleted: Bool
    ) {
        self.boundState = state
        self.boundEnteredAtMs = enteredAtMs
        self.currentIsAutoFocused = isAutoFocused
        self.toolTip = nil

        iconView.image = sprite
        titleField.font = NSFont.systemFont(ofSize: 12.0, weight: state.isActiveRunning ? .semibold : .regular)
        titleField.textColor = NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)
        titleField.stringValue = title

        costField.stringValue = costText
        costField.isHidden = costText.isEmpty

        if let chip = expandChip {
            if subTaskCount > 0 {
                chip.isHidden = false
                chip.text = isExpanded ? "▾ \(subTaskCount)" : "▸ \(subTaskCount)"
            } else {
                chip.isHidden = true
            }
        }

        alphaValue = dimmedCompleted ? 0.52 : 1.0
        updateLiveTimerText(nowMs: nowMs)
        applySurfaceAppearance()
    }

    func configureSubTask(
        state: AgentRunState,
        enteredAtMs: Int64,
        roleLabel: String,
        title: String,
        rightSummaryText: String,
        dimmedCompleted: Bool
    ) {
        self.boundState = state
        self.boundEnteredAtMs = enteredAtMs
        self.toolTip = nil

        roleBadgeField.stringValue = roleLabel
        titleField.font = NSFont.systemFont(ofSize: 11.2, weight: .regular)
        titleField.textColor = NSColor(srgbRed: 0.25, green: 0.32, blue: 0.42, alpha: 1.0)
        titleField.stringValue = title
        costField.stringValue = rightSummaryText

        alphaValue = dimmedCompleted ? 0.55 : 0.94
        applySurfaceAppearance()
    }

    func updateSpriteOnly(_ image: NSImage) {
        if !isSubTaskRow {
            iconView.image = image
        }
    }

    func updateLiveTimerText(nowMs: Int64) {
        guard !isSubTaskRow else { return }
        if boundState.isActiveRunning {
            timerField.stringValue = TimeFormatters.compactTimerOnly(enteredAtMs: boundEnteredAtMs, nowMs: nowMs)
            timerField.textColor = boundState.accentColor
        } else if boundState == .error {
            timerField.stringValue = "出错"
            timerField.textColor = boundState.accentColor
        } else {
            timerField.stringValue = "完成"
            timerField.textColor = NSColor(srgbRed: 0.56, green: 0.63, blue: 0.72, alpha: 1.0)
        }
    }

    private func applySurfaceAppearance() {
        goBadgeField.textColor = isHovered
            ? NSColor(srgbRed: 0.01, green: 0.52, blue: 0.78, alpha: 1.0)
            : NSColor(srgbRed: 0.72, green: 0.78, blue: 0.85, alpha: 1.0)

        if currentIsAutoFocused && !isSubTaskRow {
            layer?.borderColor = NSColor(srgbRed: 0.73, green: 0.90, blue: 0.99, alpha: 0.90).cgColor
            layer?.backgroundColor = isHovered
                ? NSColor(srgbRed: 0.91, green: 0.96, blue: 1.00, alpha: 1.0).cgColor
                : NSColor(srgbRed: 0.945, green: 0.978, blue: 1.00, alpha: 0.85).cgColor
        } else {
            layer?.borderColor = NSColor.clear.cgColor
            layer?.backgroundColor = isHovered
                ? NSColor(srgbRed: 0.962, green: 0.975, blue: 0.990, alpha: 1.0).cgColor
                : NSColor.clear.cgColor
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        guard super.hitTest(point) != nil else { return nil }
        if let chip = expandChip, !chip.isHidden, let sv = superview {
            let localPt = convert(point, from: sv)
            let chipPt = chip.convert(localPt, from: self)
            if chip.bounds.insetBy(dx: -4, dy: -4).contains(chipPt) {
                return chip
            }
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor(srgbRed: 0.90, green: 0.95, blue: 0.99, alpha: 1.0).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        applySurfaceAppearance()
        let pt = convert(event.locationInWindow, from: nil)
        if bounds.contains(pt), let action = onClick {
            DispatchQueue.main.async {
                action()
            }
        }
    }
}

// MARK: - In-Popover Scrollable Rounded Dropdown Card & Deterministic Overlay Container

private struct DropdownMenuItemSpec {
    enum Style {
        case standard
        case selected
        case accentAction
        case mutedBackHeader
    }
    let title: String
    let rightDetail: String
    let rightAccent: Bool
    let style: Style
    let action: () -> Void
}

private final class DropdownMenuRowControl: NSView {
    private let spec: DropdownMenuItemSpec
    private let leftLabel = NSTextField(labelWithString: "")
    private let rightLabel = NSTextField(labelWithString: "")
    private var isHovered = false
    private var isPressed = false
    private var trackingRef: NSTrackingArea?

    init(spec: DropdownMenuItemSpec, frame: NSRect) {
        self.spec = spec
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 7.5

        leftLabel.stringValue = spec.title
        leftLabel.lineBreakMode = .byTruncatingMiddle
        leftLabel.usesSingleLineMode = true
        leftLabel.translatesAutoresizingMaskIntoConstraints = false
        leftLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        rightLabel.stringValue = spec.rightDetail
        rightLabel.alignment = .right
        rightLabel.isHidden = spec.rightDetail.isEmpty
        rightLabel.usesSingleLineMode = true
        rightLabel.translatesAutoresizingMaskIntoConstraints = false
        rightLabel.setContentHuggingPriority(.required, for: .horizontal)
        rightLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(leftLabel)
        addSubview(rightLabel)

        if spec.rightDetail.isEmpty {
            NSLayoutConstraint.activate([
                leftLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                leftLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                leftLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                leftLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                leftLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                leftLabel.trailingAnchor.constraint(lessThanOrEqualTo: rightLabel.leadingAnchor, constant: -8),

                rightLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                rightLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
        updateStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        return super.hitTest(point) != nil ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingRef { removeTrackingArea(t) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateStyle()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        updateStyle()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateStyle()
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = isPressed
        isPressed = false
        updateStyle()
        let pt = convert(event.locationInWindow, from: nil)
        if wasPressed || bounds.insetBy(dx: -2, dy: -2).contains(pt) {
            if bounds.insetBy(dx: -4, dy: -4).contains(pt) {
                let action = spec.action
                DispatchQueue.main.async {
                    action()
                }
            }
        }
    }

    private func updateStyle() {
        if isPressed {
            layer?.backgroundColor = NSColor(srgbRed: 0.84, green: 0.93, blue: 1.00, alpha: 1.0).cgColor
        } else {
            switch spec.style {
            case .selected:
                layer?.backgroundColor = isHovered
                    ? NSColor(srgbRed: 0.89, green: 0.95, blue: 1.00, alpha: 1.0).cgColor
                    : NSColor(srgbRed: 0.935, green: 0.972, blue: 1.00, alpha: 1.0).cgColor
            case .accentAction:
                layer?.backgroundColor = isHovered
                    ? NSColor(srgbRed: 0.935, green: 0.972, blue: 1.00, alpha: 1.0).cgColor
                    : NSColor.clear.cgColor
            case .mutedBackHeader:
                layer?.backgroundColor = isHovered
                    ? NSColor(srgbRed: 0.935, green: 0.965, blue: 0.995, alpha: 1.0).cgColor
                    : NSColor(srgbRed: 0.968, green: 0.980, blue: 0.994, alpha: 1.0).cgColor
            case .standard:
                layer?.backgroundColor = isHovered
                    ? NSColor(srgbRed: 0.955, green: 0.972, blue: 0.992, alpha: 1.0).cgColor
                    : NSColor.clear.cgColor
            }
        }

        switch spec.style {
        case .selected:
            leftLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
            leftLabel.textColor = NSColor(srgbRed: 0.02, green: 0.36, blue: 0.56, alpha: 1.0)
            rightLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .semibold)
            rightLabel.textColor = NSColor(srgbRed: 0.02, green: 0.36, blue: 0.56, alpha: 1.0)
        case .accentAction:
            leftLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
            leftLabel.textColor = NSColor(srgbRed: 0.01, green: 0.44, blue: 0.68, alpha: 1.0)
            rightLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.8, weight: .semibold)
            rightLabel.textColor = NSColor(srgbRed: 0.01, green: 0.44, blue: 0.68, alpha: 1.0)
        case .mutedBackHeader:
            leftLabel.font = NSFont.systemFont(ofSize: 11.4, weight: .semibold)
            leftLabel.textColor = NSColor(srgbRed: 0.02, green: 0.44, blue: 0.68, alpha: 1.0)
            rightLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
            rightLabel.textColor = NSColor(srgbRed: 0.45, green: 0.53, blue: 0.62, alpha: 1.0)
        case .standard:
            leftLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
            leftLabel.textColor = NSColor(srgbRed: 0.14, green: 0.21, blue: 0.31, alpha: 1.0)
            rightLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.8, weight: spec.rightAccent ? .semibold : .medium)
            rightLabel.textColor = spec.rightAccent
                ? NSColor(srgbRed: 0.01, green: 0.44, blue: 0.68, alpha: 1.0)
                : NSColor(srgbRed: 0.45, green: 0.53, blue: 0.62, alpha: 1.0)
        }
    }
}

private final class FloatingDropdownCardView: NSView {
    private let headerContainer = NSView()
    private let headerSeparator = NSView()
    private let scrollView = NSScrollView()
    private let docView = FlippedDocumentView()

    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var scrollTopConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12.5
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor(srgbRed: 0.82, green: 0.87, blue: 0.93, alpha: 1.0).cgColor
        layer?.shadowColor = NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0).cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -6)

        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.isHidden = true
        addSubview(headerContainer)

        headerSeparator.wantsLayer = true
        headerSeparator.layer?.backgroundColor = NSColor(srgbRed: 0.90, green: 0.93, blue: 0.97, alpha: 1.0).cgColor
        headerSeparator.translatesAutoresizingMaskIntoConstraints = false
        headerSeparator.isHidden = true
        addSubview(headerSeparator)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = docView
        addSubview(scrollView)

        let wC = widthAnchor.constraint(equalToConstant: 268)
        let hC = heightAnchor.constraint(equalToConstant: 120)
        let topC = scrollView.topAnchor.constraint(equalTo: topAnchor)
        self.widthConstraint = wC
        self.heightConstraint = hC
        self.scrollTopConstraint = topC

        NSLayoutConstraint.activate([
            wC,
            hC,
            headerContainer.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            headerContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            headerContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            headerContainer.heightAnchor.constraint(equalToConstant: 30),

            headerSeparator.topAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: 4),
            headerSeparator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            headerSeparator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            headerSeparator.heightAnchor.constraint(equalToConstant: 1),

            topC,
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}

    /// Deterministic frame layout inside `FlippedDocumentView` — supports 5, 10, or 30+ console items with smooth native scrolling and zero width collapse.
    func rebuild(
        sections: [[DropdownMenuItemSpec]],
        cardWidth: CGFloat,
        maxTotalHeight: CGFloat = 386,
        pinnedBackHeader: DropdownMenuItemSpec? = nil
    ) {
        for sub in headerContainer.subviews { sub.removeFromSuperview() }
        for sub in docView.subviews { sub.removeFromSuperview() }

        let rowWidth = max(140, cardWidth - 10)
        let rowHeight: CGFloat = 29

        var pinnedHeaderOffset: CGFloat = 0
        if let backSpec = pinnedBackHeader {
            headerContainer.isHidden = false
            headerSeparator.isHidden = false
            let backRow = DropdownMenuRowControl(
                spec: backSpec,
                frame: NSRect(x: 0, y: 0, width: rowWidth, height: 30)
            )
            backRow.autoresizingMask = [.width]
            headerContainer.addSubview(backRow)
            pinnedHeaderOffset = 40
        } else {
            headerContainer.isHidden = true
            headerSeparator.isHidden = true
            pinnedHeaderOffset = 0
        }

        scrollTopConstraint?.constant = pinnedHeaderOffset

        let nonEmptySections = sections.filter { !$0.isEmpty }
        var cursorY: CGFloat = 5

        for (sIdx, section) in nonEmptySections.enumerated() {
            if sIdx > 0 {
                cursorY += 3
                let sep = NSView(frame: NSRect(x: 11, y: cursorY, width: max(80, cardWidth - 22), height: 1))
                sep.wantsLayer = true
                sep.layer?.backgroundColor = NSColor(srgbRed: 0.90, green: 0.93, blue: 0.97, alpha: 1.0).cgColor
                docView.addSubview(sep)
                cursorY += 4
            }
            for (rIdx, item) in section.enumerated() {
                if rIdx > 0 {
                    cursorY += 2
                }
                let row = DropdownMenuRowControl(
                    spec: item,
                    frame: NSRect(x: 5, y: cursorY, width: rowWidth, height: rowHeight)
                )
                docView.addSubview(row)
                cursorY += rowHeight
            }
        }

        cursorY += 5
        docView.frame = NSRect(x: 0, y: 0, width: cardWidth, height: cursorY)

        let totalHeight = min(maxTotalHeight, pinnedHeaderOffset + cursorY)
        widthConstraint?.constant = cardWidth
        heightConstraint?.constant = totalHeight
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

/// Hosts a modal or dropdown `contentCard` directly inside a full-Popover overlay so `hitTest(_:)` ALWAYS routes clicks inside `contentCard` to its interactive subviews first, and dismisses cleanly when clicking outside.
private final class ModalOverlayContainerView: NSView {
    let contentCard: NSView
    var onTapOutside: (() -> Void)?

    init(contentCard: NSView, dimmed: Bool) {
        self.contentCard = contentCard
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = dimmed
            ? NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 0.30).cgColor
            : NSColor.clear.cgColor

        contentCard.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentCard)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        let localPt = superview != nil ? convert(point, from: superview) : point
        guard bounds.contains(localPt) else { return nil }

        // Route to contentCard & its children FIRST — eliminates all sibling z-order issues inside NSVisualEffectView!
        if !contentCard.isHidden, contentCard.alphaValue > 0.01 {
            if let hitChild = contentCard.hitTest(localPt) {
                return hitChild
            }
            if contentCard.frame.contains(localPt) {
                return contentCard
            }
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let localPt = convert(event.locationInWindow, from: nil)
        if !contentCard.frame.contains(localPt), bounds.contains(localPt) {
            if let outside = onTapOutside {
                DispatchQueue.main.async {
                    outside()
                }
            }
        }
    }
}

// MARK: - In-Popover Native API-Key Manager Card (Embedded Inside NSPopover · Zero Window Loss)

private final class PasteableTextField: NSTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command, let chars = event.charactersIgnoringModifiers?.lowercased() {
                switch chars {
                case "v":
                    if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
                case "c":
                    if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
                case "x":
                    if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
                case "a":
                    if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
                case "z":
                    if NSApp.sendAction(Selector(("undo:")), to: nil, from: self) { return true }
                default:
                    break
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class APIKeyManagerPanelContentView: NSView {
    var onSaveProfile: ((String, String, String) -> Void)?
    var onSelectScope: ((String) -> Void)?
    var onDeleteProfile: ((String) -> Void)?
    var onRescanOpenCode: (() -> Void)?
    var onClose: (() -> Void)?

    private let listScroll = NSScrollView()
    private let docView = FlippedDocumentView()
    let nameField = PasteableTextField(frame: .zero)
    let secretField = PasteableTextField(frame: .zero)
    let keywordField = PasteableTextField(frame: .zero)
    private let formTitleLabel = NSTextField(labelWithString: "手动补充或覆盖分组（同名自动覆盖）")
    private let feedbackLabel = NSTextField(labelWithString: "")
    private var cachedProfiles: [APIKeyProfile] = []

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor(srgbRed: 0.78, green: 0.85, blue: 0.93, alpha: 1.0).cgColor
        layer?.shadowColor = NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0).cgColor
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 20
        layer?.shadowOffset = CGSize(width: 0, height: -8)

        let titleLabel = NSTextField(labelWithString: "API-Key 自动读取与多分组管理")
        titleLabel.font = NSFont.systemFont(ofSize: 13.5, weight: .bold)
        titleLabel.textColor = NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let rescanBtn = CapsuleControlButton(title: "↻ 重新读取DB", fontSize: 10.8)
        rescanBtn.translatesAutoresizingMaskIntoConstraints = false
        rescanBtn.onPress = { [weak self] in
            self?.handleRescanClick()
        }

        let closeBtn = CapsuleControlButton(title: "✕", fixedWidth: 28, fontSize: 11.2)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.onPress = { [weak self] in
            self?.handleCancelClick()
        }

        let headerBar = NSView()
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(titleLabel)
        headerBar.addSubview(rescanBtn)
        headerBar.addSubview(closeBtn)

        let subtitleLabel = NSTextField(
            wrappingLabelWithString: "已自动只读提取 opencode.db / auth.json / opencode.json 中的 Key 并直连 api.deepseek.com 查询实时余额；也可手动新增多组 Key。"
        )
        subtitleLabel.font = NSFont.systemFont(ofSize: 11.0, weight: .regular)
        subtitleLabel.textColor = NSColor(srgbRed: 0.40, green: 0.47, blue: 0.57, alpha: 1.0)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let existingHeader = NSTextField(labelWithString: "当前可用 Key 与自动识别通道")
        existingHeader.font = NSFont.systemFont(ofSize: 11.0, weight: .semibold)
        existingHeader.textColor = NSColor(srgbRed: 0.26, green: 0.34, blue: 0.44, alpha: 1.0)
        existingHeader.translatesAutoresizingMaskIntoConstraints = false

        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = true
        listScroll.autohidesScrollers = true
        listScroll.wantsLayer = true
        listScroll.layer?.cornerRadius = 9
        listScroll.layer?.backgroundColor = NSColor(srgbRed: 0.968, green: 0.980, blue: 0.994, alpha: 1.0).cgColor
        listScroll.layer?.borderWidth = 1.0
        listScroll.layer?.borderColor = NSColor(srgbRed: 0.87, green: 0.91, blue: 0.96, alpha: 1.0).cgColor
        listScroll.translatesAutoresizingMaskIntoConstraints = false
        listScroll.documentView = docView

        formTitleLabel.font = NSFont.systemFont(ofSize: 11.0, weight: .semibold)
        formTitleLabel.textColor = NSColor(srgbRed: 0.26, green: 0.34, blue: 0.44, alpha: 1.0)
        formTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        configureInput(nameField, placeholder: "分组名称（如：DeepSeek 官方、个人备用Key）", monospaced: false)
        configureInput(secretField, placeholder: "sk-...（支持 ⌘V 或右侧一键粘贴，用于实时查余额）", monospaced: true)
        configureInput(keywordField, placeholder: "工作目录或通道匹配词（可选，如 client-b 自动分账）", monospaced: false)

        let pasteBtn = CapsuleControlButton(title: "粘贴", fontSize: 11.0)
        pasteBtn.translatesAutoresizingMaskIntoConstraints = false
        pasteBtn.onPress = { [weak self] in
            self?.handlePasteClipboard()
        }

        let secretRow = NSView()
        secretRow.translatesAutoresizingMaskIntoConstraints = false
        secretRow.addSubview(secretField)
        secretRow.addSubview(pasteBtn)

        feedbackLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        feedbackLabel.textColor = NSColor(srgbRed: 0.02, green: 0.48, blue: 0.72, alpha: 1.0)
        feedbackLabel.lineBreakMode = .byTruncatingTail
        feedbackLabel.translatesAutoresizingMaskIntoConstraints = false

        let cancelBtn = CapsuleControlButton(title: "取消", fontSize: 11.2)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.onPress = { [weak self] in
            self?.handleCancelClick()
        }

        let saveBtn = CapsuleControlButton(title: "保存并启用", fontSize: 11.2)
        saveBtn.isTintedAccent = true
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        saveBtn.onPress = { [weak self] in
            self?.submitCurrentForm()
        }

        let actionRow = NSView()
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        actionRow.addSubview(feedbackLabel)
        actionRow.addSubview(cancelBtn)
        actionRow.addSubview(saveBtn)

        addSubview(headerBar)
        addSubview(subtitleLabel)
        addSubview(existingHeader)
        addSubview(listScroll)
        addSubview(formTitleLabel)
        addSubview(nameField)
        addSubview(secretRow)
        addSubview(keywordField)
        addSubview(actionRow)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            headerBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            headerBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            headerBar.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            closeBtn.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),
            closeBtn.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            rescanBtn.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -6),
            rescanBtn.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 7),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            existingHeader.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 9),
            existingHeader.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            existingHeader.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            listScroll.topAnchor.constraint(equalTo: existingHeader.bottomAnchor, constant: 5),
            listScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            listScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            listScroll.heightAnchor.constraint(equalToConstant: 120),

            formTitleLabel.topAnchor.constraint(equalTo: listScroll.bottomAnchor, constant: 10),
            formTitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            formTitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            nameField.topAnchor.constraint(equalTo: formTitleLabel.bottomAnchor, constant: 6),
            nameField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            secretRow.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 7),
            secretRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            secretRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            secretRow.heightAnchor.constraint(equalToConstant: 28),
            secretField.leadingAnchor.constraint(equalTo: secretRow.leadingAnchor),
            secretField.centerYAnchor.constraint(equalTo: secretRow.centerYAnchor),
            secretField.trailingAnchor.constraint(equalTo: pasteBtn.leadingAnchor, constant: -6),
            pasteBtn.trailingAnchor.constraint(equalTo: secretRow.trailingAnchor),
            pasteBtn.centerYAnchor.constraint(equalTo: secretRow.centerYAnchor),

            keywordField.topAnchor.constraint(equalTo: secretRow.bottomAnchor, constant: 7),
            keywordField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            keywordField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            actionRow.topAnchor.constraint(equalTo: keywordField.bottomAnchor, constant: 11),
            actionRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            actionRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            actionRow.heightAnchor.constraint(equalToConstant: 28),
            actionRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -15),

            feedbackLabel.leadingAnchor.constraint(equalTo: actionRow.leadingAnchor),
            feedbackLabel.centerYAnchor.constraint(equalTo: actionRow.centerYAnchor),
            feedbackLabel.trailingAnchor.constraint(lessThanOrEqualTo: cancelBtn.leadingAnchor, constant: -8),
            saveBtn.trailingAnchor.constraint(equalTo: actionRow.trailingAnchor),
            saveBtn.centerYAnchor.constraint(equalTo: actionRow.centerYAnchor),
            cancelBtn.trailingAnchor.constraint(equalTo: saveBtn.leadingAnchor, constant: -7),
            cancelBtn.centerYAnchor.constraint(equalTo: actionRow.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureInput(_ tf: PasteableTextField, placeholder: String, monospaced: Bool) {
        tf.isEditable = true
        tf.isSelectable = true
        tf.isBezeled = true
        tf.bezelStyle = .roundedBezel
        tf.drawsBackground = true
        tf.backgroundColor = .white
        tf.textColor = NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)
        tf.placeholderString = placeholder
        tf.font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
            : NSFont.systemFont(ofSize: 12.0, weight: .regular)
        tf.focusRingType = .exterior
        tf.lineBreakMode = .byTruncatingMiddle
        tf.usesSingleLineMode = true
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    func reloadProfiles(_ profiles: [APIKeyProfile], selectedScopeId: String, resetInputs: Bool) {
        for sub in docView.subviews { sub.removeFromSuperview() }

        let innerW: CGFloat = 396 - 12
        var cursorY: CGFloat = 5

        for profile in profiles {
            let row = NSView(frame: NSRect(x: 6, y: cursorY, width: innerW, height: 30))
            row.wantsLayer = true
            row.layer?.cornerRadius = 7
            let isSelected = (profile.id == selectedScopeId)
            row.layer?.backgroundColor = isSelected
                ? NSColor(srgbRed: 0.91, green: 0.96, blue: 1.00, alpha: 1.0).cgColor
                : NSColor.white.cgColor
            row.layer?.borderWidth = 1.0
            row.layer?.borderColor = isSelected
                ? NSColor(srgbRed: 0.68, green: 0.86, blue: 0.98, alpha: 1.0).cgColor
                : NSColor(srgbRed: 0.89, green: 0.93, blue: 0.97, alpha: 1.0).cgColor

            let sourceTag: String
            if let src = profile.autoSource, !src.isEmpty {
                sourceTag = "自动 · \(src)"
            } else if !profile.directoryKeyword.isEmpty {
                sourceTag = "目录:\(profile.directoryKeyword)"
            } else {
                sourceTag = "手动添加"
            }

            let label = NSTextField(labelWithString: "\(profile.displayTitle)  ·  \(sourceTag)")
            label.font = NSFont.systemFont(ofSize: 11.2, weight: isSelected ? .semibold : .medium)
            label.textColor = isSelected
                ? NSColor(srgbRed: 0.01, green: 0.43, blue: 0.66, alpha: 1.0)
                : NSColor(srgbRed: 0.15, green: 0.22, blue: 0.32, alpha: 1.0)
            label.lineBreakMode = .byTruncatingMiddle
            label.usesSingleLineMode = true
            label.translatesAutoresizingMaskIntoConstraints = false

            let pid = profile.id
            let editChip = SubCountChipControl(frame: .zero)
            editChip.text = "编辑"
            editChip.translatesAutoresizingMaskIntoConstraints = false
            editChip.onTap = { [weak self] in
                self?.populateEditor(profileId: pid)
            }

            let useChip = SubCountChipControl(frame: .zero)
            useChip.text = isSelected ? "当前✓" : "启用"
            useChip.translatesAutoresizingMaskIntoConstraints = false
            useChip.onTap = { [weak self] in
                guard let self, !isSelected else { return }
                self.window?.endEditing(for: nil)
                self.onSelectScope?(pid)
                self.onClose?()
            }

            let rightButtons = NSStackView(views: [editChip, useChip])
            rightButtons.orientation = .horizontal
            rightButtons.alignment = .centerY
            rightButtons.spacing = 4
            rightButtons.translatesAutoresizingMaskIntoConstraints = false

            if !profile.isAutoDiscovered {
                let delChip = SubCountChipControl(frame: .zero)
                delChip.text = "删除"
                delChip.translatesAutoresizingMaskIntoConstraints = false
                delChip.onTap = { [weak self] in
                    self?.window?.endEditing(for: nil)
                    self?.onDeleteProfile?(pid)
                }
                rightButtons.addArrangedSubview(delChip)
            }

            row.addSubview(label)
            row.addSubview(rightButtons)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
                label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: rightButtons.leadingAnchor, constant: -6),
                rightButtons.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -6),
                rightButtons.centerYAnchor.constraint(equalTo: row.centerYAnchor)
            ])

            docView.addSubview(row)
            cursorY += 34
        }

        docView.frame = NSRect(x: 0, y: 0, width: 396, height: max(118, cursorY + 2))
        cachedProfiles = profiles

        if resetInputs {
            feedbackLabel.stringValue = profiles.contains(where: { $0.isAutoDiscovered })
                ? "已自动同步本机 OpenCode 密钥"
                : ""
            if profiles.count == 1 && profiles[0].rawApiKey.isEmpty && !profiles[0].isAutoDiscovered {
                formTitleLabel.stringValue = "完善默认主Key 或输入新名称新增分组"
                nameField.stringValue = profiles[0].name
                secretField.stringValue = ""
                keywordField.stringValue = profiles[0].directoryKeyword
            } else {
                formTitleLabel.stringValue = "手动补充或覆盖分组（同名自动覆盖）"
                nameField.stringValue = ""
                secretField.stringValue = ""
                keywordField.stringValue = ""
            }
        }
    }

    var preferredInitialField: NSView {
        nameField.stringValue.isEmpty ? nameField : secretField
    }

    private func populateEditor(profileId: String) {
        window?.endEditing(for: nil)
        guard let prof = cachedProfiles.first(where: { $0.id == profileId }) else { return }
        formTitleLabel.stringValue = "正在编辑：\(prof.name)"
        nameField.stringValue = prof.name
        secretField.stringValue = prof.rawApiKey
        keywordField.stringValue = prof.directoryKeyword
        window?.makeFirstResponder(secretField)
    }

    private func handlePasteClipboard() {
        window?.endEditing(for: nil)
        if let str = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !str.isEmpty {
            secretField.stringValue = str
            if nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nameField.stringValue = cachedProfiles.isEmpty ? "DeepSeek 官方" : "备用Key-\(cachedProfiles.count + 1)"
            }
            feedbackLabel.stringValue = "已粘贴 (\(APIKeyProfile.makeMasked(str)))"
            window?.makeFirstResponder(secretField)
        } else {
            feedbackLabel.stringValue = "剪贴板暂无文本"
        }
    }

    private func handleRescanClick() {
        feedbackLabel.stringValue = "正在重新扫描 opencode.db / auth.json…"
        onRescanOpenCode?()
    }

    private func handleCancelClick() {
        window?.endEditing(for: nil)
        onClose?()
    }

    func submitCurrentForm() {
        window?.endEditing(for: nil)
        window?.makeFirstResponder(nil)
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = secretField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let kw = keywordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty || !secret.isEmpty || !kw.isEmpty else {
            feedbackLabel.stringValue = "请填写名称或粘贴 sk-... 密钥"
            window?.makeFirstResponder(secretField)
            return
        }
        let finalName = name.isEmpty ? "备用Key-\(cachedProfiles.count + 1)" : name
        onSaveProfile?(finalName, secret, kw)
    }
}

// MARK: - Minimalist Status Bar Popover View Controller (1:1 Design Parity)

final class StatusPopoverViewController: NSViewController {
    var onRefreshQuota: (() -> Void)?
    var onSelectCurrencyMode: ((CurrencyDisplayMode) -> Void)?
    var onSelectApiKeyScope: ((String) -> Void)?
    var onSaveApiKeyProfile: ((String, String, String) -> Void)?
    var onDeleteApiKeyProfile: ((String) -> Void)?
    var onToggleNotificationsMuted: (() -> Void)?
    var onTestNotificationSound: (() -> Void)?
    var onToggleAutoFocus: ((Bool) -> Void)?
    var onSelectRealWindowId: ((String?) -> Void)?
    var onSelectPackId: ((String) -> Void)?
    var onImportCustomPack: ((DeepSeekRolePack) -> Void)?
    var onImportOfficialCSVs: ((OfficialCSVReconciliation) -> Void)?
    var onClearOfficialCSV: (() -> Void)?
    var onFilterChanged: (() -> Void)?
    var onRequestClosePopover: (() -> Void)?
    var onModalPanelStateChange: ((Bool) -> Void)?
    var onSelectMenuBarDisplayMode: ((MenuBarDisplayMode) -> Void)?
    var onSelectFloatingBadgeMode: ((FloatingBadgeMode) -> Void)?
    var onToggleLaunchAtLogin: ((Bool) -> Void)?
    var onQuitApp: (() -> Void)?

    // Top Identity & Aligned 28pt Capsule Controls
    private let brandIconView = RetinaAspectFitImageView(pointSize: 22)
    private let brandTitleLabel = NSTextField(labelWithString: "AgentSpur")
    private let statusCapsule = RunningStatusCapsuleView()

    private let keySelectorCapsule = CapsuleControlButton(title: "🔑 全部 Key ▾", fontSize: 11.0)
    private let refreshCapsule = CapsuleControlButton(title: "↻ ⌘R", fontSize: 11.0, monospaced: true)
    private let settingsCapsule = CapsuleControlButton(title: "设置", symbolName: "gearshape", fixedWidth: 28)

    // Minimalist Hero Spend & Cache Bar Card + Custom Floating Breakdown Card
    private let billingCard = BillingTelemetryCardView()
    private let hoverBreakdownCard = CostBreakdownHoverCardView()

    // Full-Width 4-Column Segmented Filter Bar & Minimalist Accordion List
    private let filterSegmentBar = SegmentedFilterBarView()

    // 24H Sparkline Bar Chart
    private let chartHoverLabel = NSTextField(labelWithString: "00:00 - 24:00 · 悬停看明细")
    private let sparklineView = SparklineBarChartView()

    // Clean Single-Row Footer Toolbar
    private let rolePackCapsule = CapsuleControlButton(title: "🐳 深海小鲸 ▾", fontSize: 11.0)
    private let bellToggleCapsule = CapsuleControlButton(title: "🔔 提醒开启", fontSize: 11.0)
    private let quitCapsule = CapsuleControlButton(title: "✕ 退出", fontSize: 11.0)

    // In-Popover Scrollable Dropdown Card + Modal Overlay
    private enum ActiveDropdownKind {
        case none
        case keyAndCurrency
        case settingsGear
        case consoleSelector
        case rolePack
    }
    private var activeDropdown: ActiveDropdownKind = .none
    private let dropdownCard = FloatingDropdownCardView()
    private lazy var dropdownOverlay = ModalOverlayContainerView(contentCard: dropdownCard, dimmed: false)
    private var dropdownPositionConstraints: [NSLayoutConstraint] = []

    // In-Popover Dimmed Modal Overlay + Embedded API-Key Manager Card (Zero External Window · 100% Reliable)
    private let apiKeyPanelContent = APIKeyManagerPanelContentView(frame: .zero)
    private lazy var apiKeyModalOverlay = ModalOverlayContainerView(contentCard: apiKeyPanelContent, dimmed: true)

    // Session list document view (pure Auto Layout, zero NSStackView width drift)
    private let sessionDocContainer = FlippedDocumentView()
    private var activeRowViews: [SessionRowView] = []
    private var expandedMasterIds = Set<String>()

    var isApiKeyModalVisible: Bool {
        !apiKeyModalOverlay.isHidden
    }

    // Cached render state
    private var currentFilter: SessionGroupFilter = .all
    private var lastSnapshot: OpenCodeDBSnapshot?
    private var lastApiKeyProfiles: [APIKeyProfile] = []
    private var lastCurrencyMode: CurrencyDisplayMode = .cny
    private var lastUsdToCnyRate: Double = 7.12
    private var lastSelectedKeyScopeId: String = APIKeyProfile.allKeysId
    private var lastAutoFocusEnabled: Bool = true
    private var lastSelectedWindowId: String? = nil
    private var lastCsvReconciliation: OfficialCSVReconciliation?
    private var lastAllPacks: [DeepSeekRolePack] = DeepSeekRolePack.builtInPacks
    private var lastActivePackId: String = "pack-gin-droplet"
    private var lastMenuBarDisplayMode: MenuBarDisplayMode = .iconOnly
    private var lastFloatingBadgeMode: FloatingBadgeMode = .autoWhenOccluded
    private var lastLaunchAtLoginEnabled: Bool = false
    private var keyMonitor: Any?

    override func loadView() {
        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 464, height: 556))
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .aqua)

        let porcelainTint = NSView()
        porcelainTint.wantsLayer = true
        porcelainTint.layer?.backgroundColor = NSColor(srgbRed: 0.973, green: 0.982, blue: 0.994, alpha: 0.96).cgColor
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
        setupFloatingOverlays()
        setupApiKeyPanelCallbacks()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.isApiKeyModalVisible {
                if event.keyCode == 53 { // Esc 关闭内嵌 API-Key 弹窗并保持主面板开启
                    self.dismissApiKeyPanelIfVisible()
                    return nil
                }
                if event.keyCode == 36 || event.keyCode == 76 { // Return 直接保存
                    self.apiKeyPanelContent.submitCurrentForm()
                    return nil
                }
                return event
            }
            if self.activeDropdown != .none, event.keyCode == 53 {
                if self.activeDropdown == .consoleSelector {
                    self.toggleSettingsGearDropdown()
                } else {
                    self.dismissDropdownMenu()
                }
                return nil
            }
            if event.keyCode == 53 {
                self.onRequestClosePopover?()
                return nil
            }
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "r" {
                self.onRefreshQuota?()
                return nil
            }
            return event
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        dismissDropdownMenu()
        hoverBreakdownCard.isHidden = true
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func setupLayout() {
        // Explicit symmetrical 16pt horizontal margins across 464pt Popover (contentWidth = 432pt, zero NSStackView left-shift)
        let padX: CGFloat = 16

        // 1. Minimalist Header: [22x22 Logo] AgentSpur [● 正在工作 34m 59s]  <spacer>  [🔑 Key ▾] [↻ ⌘R] [⚙︎]
        brandIconView.image = SpriteRenderer.renderBrandLogoImage(pointSize: 22)

        brandTitleLabel.font = NSFont.systemFont(ofSize: 13.5, weight: .bold)
        brandTitleLabel.textColor = NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)
        brandTitleLabel.setContentHuggingPriority(.required, for: .horizontal)
        brandTitleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        statusCapsule.setContentHuggingPriority(.required, for: .horizontal)
        statusCapsule.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let identityGroup = NSStackView(views: [brandIconView, brandTitleLabel, statusCapsule])
        identityGroup.orientation = .horizontal
        identityGroup.alignment = .centerY
        identityGroup.spacing = 6.5
        identityGroup.translatesAutoresizingMaskIntoConstraints = false

        keySelectorCapsule.widthAnchor.constraint(lessThanOrEqualToConstant: 118).isActive = true
        keySelectorCapsule.onPress = { [weak self] in
            self?.toggleKeyAndCurrencyDropdown()
        }

        refreshCapsule.onPress = { [weak self] in
            self?.dismissDropdownMenu()
            self?.onRefreshQuota?()
        }

        settingsCapsule.onPress = { [weak self] in
            self?.toggleSettingsGearDropdown()
        }

        let controlGroup = NSStackView(views: [keySelectorCapsule, refreshCapsule, settingsCapsule])
        controlGroup.orientation = .horizontal
        controlGroup.alignment = .centerY
        controlGroup.spacing = 5
        controlGroup.translatesAutoresizingMaskIntoConstraints = false
        controlGroup.setContentHuggingPriority(.required, for: .horizontal)
        controlGroup.setContentCompressionResistancePriority(.required, for: .horizontal)

        let headerBar = NSView()
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(identityGroup)
        headerBar.addSubview(controlGroup)
        view.addSubview(headerBar)

        // 2. Symmetrical Cost & Cache Overview Card (Exact 432pt Centered)
        billingCard.translatesAutoresizingMaskIntoConstraints = false
        billingCard.onExitCSVMode = { [weak self] in
            self?.onClearOfficialCSV?()
        }
        billingCard.onClickBalanceArea = { [weak self] in
            self?.presentApiKeyPanel()
        }
        billingCard.onHoverStateChange = { [weak self] hovering in
            guard let self else { return }
            if hovering && self.activeDropdown == .none && !self.isApiKeyModalVisible {
                self.hoverBreakdownCard.alphaValue = 1.0
                self.hoverBreakdownCard.isHidden = false
            } else {
                self.hoverBreakdownCard.isHidden = true
            }
        }
        view.addSubview(billingCard)

        // 3. Full-Width 4-Column Segmented Filter Bar (Exact 432pt Centered)
        filterSegmentBar.translatesAutoresizingMaskIntoConstraints = false
        filterSegmentBar.onSelectIndex = { [weak self] idx in
            guard let self else { return }
            self.dismissDropdownMenu()
            self.currentFilter = SessionGroupFilter(rawValue: idx) ?? .all
            self.onFilterChanged?()
        }
        view.addSubview(filterSegmentBar)

        // 4. Clean Accordion Session List Container (Exact 432pt Centered)
        let listContainer = NSView()
        listContainer.wantsLayer = true
        listContainer.layer?.cornerRadius = 11.5
        listContainer.layer?.backgroundColor = NSColor.white.cgColor
        listContainer.layer?.borderWidth = 1.0
        listContainer.layer?.borderColor = NSColor(srgbRed: 0.87, green: 0.91, blue: 0.95, alpha: 1.0).cgColor
        listContainer.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        sessionDocContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = sessionDocContainer
        listContainer.addSubview(scrollView)
        view.addSubview(listContainer)

        // 5. Compact 24H Sparkline Bar Chart (Exact 432pt Centered)
        let chartTitle = NSTextField(labelWithString: "24H 趋势")
        chartTitle.font = NSFont.systemFont(ofSize: 11.2, weight: .semibold)
        chartTitle.textColor = NSColor(srgbRed: 0.30, green: 0.38, blue: 0.48, alpha: 1.0)
        chartTitle.translatesAutoresizingMaskIntoConstraints = false

        chartHoverLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        chartHoverLabel.textColor = NSColor(srgbRed: 0.52, green: 0.59, blue: 0.68, alpha: 1.0)
        chartHoverLabel.alignment = .right
        chartHoverLabel.translatesAutoresizingMaskIntoConstraints = false

        let chartHeader = NSView()
        chartHeader.translatesAutoresizingMaskIntoConstraints = false
        chartHeader.addSubview(chartTitle)
        chartHeader.addSubview(chartHoverLabel)
        view.addSubview(chartHeader)

        sparklineView.translatesAutoresizingMaskIntoConstraints = false
        sparklineView.onHoverReadoutChange = { [weak self] text in
            guard let self else { return }
            self.chartHoverLabel.stringValue = text ?? "00:00 - 24:00 · 悬停看明细"
            self.chartHoverLabel.textColor = text != nil
                ? NSColor(srgbRed: 0.02, green: 0.44, blue: 0.68, alpha: 1.0)
                : NSColor(srgbRed: 0.52, green: 0.59, blue: 0.68, alpha: 1.0)
        }
        view.addSubview(sparklineView)

        // 6. Clean Single-Row Footer Toolbar: [🐳 深海小鲸 ▾]  <spacer>  [🔔 提醒开启] [✕ 退出]
        rolePackCapsule.translatesAutoresizingMaskIntoConstraints = false
        rolePackCapsule.onPress = { [weak self] in
            self?.toggleRolePackDropdown()
        }

        bellToggleCapsule.translatesAutoresizingMaskIntoConstraints = false
        bellToggleCapsule.onPress = { [weak self] in
            self?.dismissDropdownMenu()
            self?.onToggleNotificationsMuted?()
        }

        quitCapsule.translatesAutoresizingMaskIntoConstraints = false
        quitCapsule.onPress = { [weak self] in
            self?.onQuitApp?()
        }

        let footerToolbar = NSView()
        footerToolbar.translatesAutoresizingMaskIntoConstraints = false
        footerToolbar.addSubview(rolePackCapsule)
        footerToolbar.addSubview(bellToggleCapsule)
        footerToolbar.addSubview(quitCapsule)
        view.addSubview(footerToolbar)

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 464),

            // Header Bar
            headerBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 15),
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padX),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padX),
            headerBar.heightAnchor.constraint(equalToConstant: 28),

            identityGroup.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            identityGroup.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            identityGroup.trailingAnchor.constraint(lessThanOrEqualTo: controlGroup.leadingAnchor, constant: -6),

            controlGroup.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),
            controlGroup.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            // Billing Card
            billingCard.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 12),
            billingCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padX),
            billingCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padX),

            // Segmented Filter Bar
            filterSegmentBar.topAnchor.constraint(equalTo: billingCard.bottomAnchor, constant: 12),
            filterSegmentBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padX),
            filterSegmentBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padX),

            // Session List Container
            listContainer.topAnchor.constraint(equalTo: filterSegmentBar.bottomAnchor, constant: 10),
            listContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padX),
            listContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padX),
            listContainer.heightAnchor.constraint(equalToConstant: 204),

            scrollView.topAnchor.constraint(equalTo: listContainer.topAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor, constant: 6),
            scrollView.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor, constant: -6),
            scrollView.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor, constant: -6),

            sessionDocContainer.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            sessionDocContainer.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            sessionDocContainer.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            // 24H Trend Header & Sparkline
            chartHeader.topAnchor.constraint(equalTo: listContainer.bottomAnchor, constant: 12),
            chartHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padX),
            chartHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padX),
            chartHeader.heightAnchor.constraint(equalToConstant: 16),

            chartTitle.leadingAnchor.constraint(equalTo: chartHeader.leadingAnchor),
            chartTitle.centerYAnchor.constraint(equalTo: chartHeader.centerYAnchor),
            chartHoverLabel.trailingAnchor.constraint(equalTo: chartHeader.trailingAnchor),
            chartHoverLabel.centerYAnchor.constraint(equalTo: chartHeader.centerYAnchor),
            chartHoverLabel.leadingAnchor.constraint(greaterThanOrEqualTo: chartTitle.trailingAnchor, constant: 8),

            sparklineView.topAnchor.constraint(equalTo: chartHeader.bottomAnchor, constant: 5),
            sparklineView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padX),
            sparklineView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padX),
            sparklineView.heightAnchor.constraint(equalToConstant: 54),

            // Footer Toolbar
            footerToolbar.topAnchor.constraint(equalTo: sparklineView.bottomAnchor, constant: 12),
            footerToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padX),
            footerToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padX),
            footerToolbar.heightAnchor.constraint(equalToConstant: 28),
            footerToolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),

            rolePackCapsule.leadingAnchor.constraint(equalTo: footerToolbar.leadingAnchor),
            rolePackCapsule.centerYAnchor.constraint(equalTo: footerToolbar.centerYAnchor),
            quitCapsule.trailingAnchor.constraint(equalTo: footerToolbar.trailingAnchor),
            quitCapsule.centerYAnchor.constraint(equalTo: footerToolbar.centerYAnchor),
            bellToggleCapsule.trailingAnchor.constraint(equalTo: quitCapsule.leadingAnchor, constant: -6),
            bellToggleCapsule.centerYAnchor.constraint(equalTo: footerToolbar.centerYAnchor)
        ])
    }

    private func setupFloatingOverlays() {
        // 1. Symmetrical Dark Cost Breakdown Hover Card (Flush-aligned 1:1 with billingCard, centered in Popover)
        hoverBreakdownCard.isHidden = true
        hoverBreakdownCard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hoverBreakdownCard)

        // 2. In-Popover Dropdown Overlay (hosts dropdownCard directly inside itself for deterministic hitTest)
        dropdownOverlay.isHidden = true
        dropdownOverlay.translatesAutoresizingMaskIntoConstraints = false
        dropdownOverlay.onTapOutside = { [weak self] in
            self?.dismissDropdownMenu()
        }
        view.addSubview(dropdownOverlay)

        // 3. In-Popover Dimmed Modal Overlay (hosts apiKeyPanelContent directly inside itself)
        apiKeyModalOverlay.isHidden = true
        apiKeyModalOverlay.translatesAutoresizingMaskIntoConstraints = false
        apiKeyModalOverlay.onTapOutside = { [weak self] in
            self?.dismissApiKeyPanelIfVisible()
        }
        view.addSubview(apiKeyModalOverlay)

        NSLayoutConstraint.activate([
            hoverBreakdownCard.topAnchor.constraint(equalTo: billingCard.bottomAnchor, constant: 6),
            hoverBreakdownCard.leadingAnchor.constraint(equalTo: billingCard.leadingAnchor),
            hoverBreakdownCard.trailingAnchor.constraint(equalTo: billingCard.trailingAnchor),

            dropdownOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            dropdownOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dropdownOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dropdownOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            apiKeyModalOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            apiKeyModalOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            apiKeyModalOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            apiKeyModalOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            apiKeyPanelContent.centerXAnchor.constraint(equalTo: apiKeyModalOverlay.centerXAnchor),
            apiKeyPanelContent.centerYAnchor.constraint(equalTo: apiKeyModalOverlay.centerYAnchor),
            apiKeyPanelContent.widthAnchor.constraint(equalToConstant: 428)
        ])
    }

    private func setupApiKeyPanelCallbacks() {
        apiKeyPanelContent.onClose = { [weak self] in
            self?.dismissApiKeyPanelIfVisible()
        }
        apiKeyPanelContent.onRescanOpenCode = { [weak self] in
            self?.onRefreshQuota?()
        }
        apiKeyPanelContent.onSelectScope = { [weak self] scopeId in
            self?.onSelectApiKeyScope?(scopeId)
        }
        apiKeyPanelContent.onDeleteProfile = { [weak self] profileId in
            self?.onDeleteApiKeyProfile?(profileId)
        }
        apiKeyPanelContent.onSaveProfile = { [weak self] name, secret, kw in
            guard let self else { return }
            self.onSaveApiKeyProfile?(name, secret, kw)
            self.dismissApiKeyPanelIfVisible()
        }
    }

    // MARK: - In-Popover Embedded API-Key Modal Lifecycle (Never Leaves _NSPopoverWindow)

    private func presentApiKeyPanel() {
        dismissDropdownMenu()
        hoverBreakdownCard.isHidden = true

        apiKeyPanelContent.reloadProfiles(
            lastApiKeyProfiles,
            selectedScopeId: lastSelectedKeyScopeId,
            resetInputs: true
        )

        onModalPanelStateChange?(true)
        apiKeyPanelContent.alphaValue = 1.0
        apiKeyPanelContent.isHidden = false
        apiKeyModalOverlay.alphaValue = 1.0
        apiKeyModalOverlay.isHidden = false
        view.layoutSubtreeIfNeeded()

        NSApplication.shared.activate()
        view.window?.makeKey()
        view.window?.makeFirstResponder(apiKeyPanelContent.preferredInitialField)
    }

    func dismissApiKeyPanelIfVisible() {
        view.window?.endEditing(for: nil)
        view.window?.makeFirstResponder(nil)
        apiKeyModalOverlay.isHidden = true
        onModalPanelStateChange?(false)
        view.window?.makeKey()
    }

    func forceDismissAllOverlays() {
        dismissDropdownMenu()
        hoverBreakdownCard.isHidden = true
        view.window?.endEditing(for: nil)
        apiKeyModalOverlay.isHidden = true
        onModalPanelStateChange?(false)
    }

    // MARK: - 15 FPS Sprite Update & 1 Hz Timer Update (Zero View Rebuilds)

    func tickAnimationFrame(topState: AgentRunState, activePack: DeepSeekRolePack, frameIndex: Int) {
        guard isViewLoaded else { return }
        for row in activeRowViews where !row.isSubTaskRow {
            row.updateSpriteOnly(
                SpriteRenderer.renderSpriteFrame(
                    state: row.boundState,
                    pack: activePack,
                    frame: frameIndex,
                    pointSize: 18
                )
            )
        }
    }

    func tickOneSecondTimers(topState: AgentRunState, topEnteredAtMs: Int64) {
        guard isViewLoaded else { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        statusCapsule.update(state: topState, enteredAtMs: topEnteredAtMs, nowMs: nowMs)
        for row in activeRowViews {
            row.updateLiveTimerText(nowMs: nowMs)
        }
    }

    // MARK: - Full Data Render (Reads O(1) Pre-Aggregated Scope in <0.2ms)

    func renderSnapshot(
        snapshot: OpenCodeDBSnapshot,
        apiKeyProfiles: [APIKeyProfile],
        selectedKeyScopeId: String,
        quota: QuotaSnapshot,
        currencyMode: CurrencyDisplayMode,
        csvReconciliation: OfficialCSVReconciliation?,
        activePack: DeepSeekRolePack,
        allPacks: [DeepSeekRolePack],
        frameIndex: Int,
        autoFocusEnabled: Bool,
        selectedWindowId: String?,
        notificationsMuted: Bool,
        menuBarDisplayMode: MenuBarDisplayMode,
        floatingBadgeMode: FloatingBadgeMode,
        launchAtLoginEnabled: Bool
    ) {
        guard isViewLoaded else { return }
        self.lastSnapshot = snapshot
        self.lastApiKeyProfiles = apiKeyProfiles
        self.lastSelectedKeyScopeId = selectedKeyScopeId
        self.lastCurrencyMode = currencyMode
        self.lastAutoFocusEnabled = autoFocusEnabled
        self.lastSelectedWindowId = selectedWindowId
        self.lastCsvReconciliation = csvReconciliation
        self.lastAllPacks = allPacks
        self.lastActivePackId = activePack.id
        self.lastMenuBarDisplayMode = menuBarDisplayMode
        self.lastFloatingBadgeMode = floatingBadgeMode
        self.lastLaunchAtLoginEnabled = launchAtLoginEnabled

        if isApiKeyModalVisible {
            apiKeyPanelContent.reloadProfiles(
                apiKeyProfiles,
                selectedScopeId: selectedKeyScopeId,
                resetInputs: false
            )
        } else if activeDropdown == .consoleSelector {
            // Keep multi-console list live when rescan finishes
            showConsoleSelectorDropdown()
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let currentWindow = DeepSeekPricingEngine.priceWindow()
        let safeRate = max(1.0, quota.usdToCnyRate)
        self.lastUsdToCnyRate = safeRate

        let scope = snapshot.scoped(for: selectedKeyScopeId)

        // 1. Header Identity & 28pt Capsule Controls
        statusCapsule.update(
            state: snapshot.topState,
            enteredAtMs: snapshot.topStateEnteredAtMs,
            nowMs: nowMs
        )

        let shortScopeTitle = scope.title.count > 9 ? String(scope.title.prefix(9)) + "…" : scope.title
        keySelectorCapsule.text = "🔑 \(shortScopeTitle) ▾"
        keySelectorCapsule.isTintedAccent = (selectedKeyScopeId != APIKeyProfile.allKeysId)

        rolePackCapsule.text = "\(activePack.menuTitle) ▾"

        if notificationsMuted {
            bellToggleCapsule.text = "🔕 已静音"
            bellToggleCapsule.isTintedAccent = false
        } else {
            bellToggleCapsule.text = "🔔 提醒开启"
            bellToggleCapsule.isTintedAccent = true
        }

        // 2. Hero Cost & Cache Card + Symmetrical Hover Breakdown Content
        billingCard.update(
            scopeTitle: scope.title,
            billing: scope.billing,
            csvReconciliation: csvReconciliation,
            quota: quota,
            currencyMode: currencyMode,
            currentWindow: currentWindow
        )
        hoverBreakdownCard.configure(
            billing: scope.billing,
            csvReconciliation: csvReconciliation,
            quota: quota
        )

        // 3. Full-Width 4-Column Segmented Filter Bar & Minimalist Session List
        let scopedMasters = scope.masters
        let pending = scopedMasters.filter { $0.state == .confirm }
        let running = scopedMasters.filter { $0.state == .thinking || $0.state == .working }
        let completed = scopedMasters.filter { $0.state == .completed || $0.state == .error }

        filterSegmentBar.selectedIndex = currentFilter.rawValue
        filterSegmentBar.updateLabels([
            "全部 \(scopedMasters.count)",
            "待处理 \(pending.count)",
            "运行中 \(running.count)",
            "已完成 \(completed.count)"
        ])

        for sub in sessionDocContainer.subviews {
            sub.removeFromSuperview()
        }
        activeRowViews.removeAll()

        let visibleMasters: [MasterSessionItem]
        switch currentFilter {
        case .all:       visibleMasters = scopedMasters
        case .pending:   visibleMasters = pending
        case .running:   visibleMasters = running
        case .completed: visibleMasters = completed
        }

        if visibleMasters.isEmpty {
            let emptyMsg = snapshot.dbExists
                ? "当前筛选分组暂无会话"
                : "等待 ~/.local/share/opencode/ 产生会话"
            let emptyLabel = NSTextField(labelWithString: emptyMsg)
            emptyLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
            emptyLabel.textColor = NSColor(srgbRed: 0.56, green: 0.63, blue: 0.72, alpha: 1.0)
            emptyLabel.alignment = .center
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            sessionDocContainer.addSubview(emptyLabel)
            NSLayoutConstraint.activate([
                emptyLabel.topAnchor.constraint(equalTo: sessionDocContainer.topAnchor, constant: 82),
                emptyLabel.leadingAnchor.constraint(equalTo: sessionDocContainer.leadingAnchor, constant: 12),
                emptyLabel.trailingAnchor.constraint(equalTo: sessionDocContainer.trailingAnchor, constant: -12),
                emptyLabel.bottomAnchor.constraint(equalTo: sessionDocContainer.bottomAnchor, constant: -16)
            ])
        } else {
            // 仅高亮最优先的 1 条匹配前台终端的主会话，杜绝同一仓库多条历史会话全部变蓝
            let primaryFocusedMasterId: String? = autoFocusEnabled
                ? visibleMasters.first(where: { shouldHighlightWindow($0.matchedWindow, selectedWindowId: selectedWindowId) })?.id
                : nil

            var previousRow: NSView? = nil

            for m in visibleMasters {
                let row = SessionRowView(isSubTask: false)
                row.translatesAutoresizingMaskIntoConstraints = false
                let mSprite = SpriteRenderer.renderSpriteFrame(
                    state: m.state,
                    pack: activePack,
                    frame: frameIndex,
                    pointSize: 18
                )
                let costStr = m.spurCostCny > 0
                    ? DeepSeekPricingEngine.formatMoney(
                        amountCny: m.spurCostCny,
                        mode: currencyMode,
                        usdToCnyRate: safeRate,
                        highPrecision: m.spurCostCny < 0.1
                    )
                    : ""
                let mFocused = (m.id == primaryFocusedMasterId)
                let isExpanded = expandedMasterIds.contains(m.id)
                let dimCompleted = (currentFilter == .all && m.state == .completed)

                row.configureMaster(
                    state: m.state,
                    enteredAtMs: m.stateEnteredAtMs,
                    sprite: mSprite,
                    title: m.title,
                    costText: costStr,
                    nowMs: nowMs,
                    subTaskCount: m.subTasks.count,
                    isExpanded: isExpanded,
                    isAutoFocused: mFocused,
                    dimmedCompleted: dimCompleted
                )
                row.onClick = { [weak self] in
                    self?.onRequestClosePopover?()
                    TerminalBridge.jumpToRealWindow(m.matchedWindow, fallbackDirectory: m.directory)
                }
                let masterId = m.id
                row.onToggleExpand = { [weak self] in
                    guard let self else { return }
                    if self.expandedMasterIds.contains(masterId) {
                        self.expandedMasterIds.remove(masterId)
                    } else {
                        self.expandedMasterIds.insert(masterId)
                    }
                    self.onFilterChanged?()
                }
                sessionDocContainer.addSubview(row)
                NSLayoutConstraint.activate([
                    row.topAnchor.constraint(
                        equalTo: previousRow?.bottomAnchor ?? sessionDocContainer.topAnchor,
                        constant: previousRow == nil ? 0 : 2.5
                    ),
                    row.leadingAnchor.constraint(equalTo: sessionDocContainer.leadingAnchor),
                    row.trailingAnchor.constraint(equalTo: sessionDocContainer.trailingAnchor)
                ])
                previousRow = row
                activeRowViews.append(row)

                guard isExpanded else { continue }

                for sub in m.subTasks {
                    let subRow = SessionRowView(isSubTask: true)
                    subRow.translatesAutoresizingMaskIntoConstraints = false
                    let cleanSubTitle = sub.title
                        .replacingOccurrences(of: " (\(sub.roleLabel) subagent)", with: "")
                        .replacingOccurrences(of: "(\(sub.roleLabel) subagent)", with: "")

                    var rightParts: [String] = []
                    if sub.spurCostCny > 0 {
                        rightParts.append(DeepSeekPricingEngine.formatMoney(
                            amountCny: sub.spurCostCny,
                            mode: currencyMode,
                            usdToCnyRate: safeRate,
                            highPrecision: sub.spurCostCny < 0.1
                        ))
                    }
                    if (sub.inputCacheHitTokens + sub.inputCacheMissTokens) > 0 {
                        rightParts.append(String(format: "%.0f%%", sub.cacheHitPercent))
                    }
                    if sub.state.isActiveRunning {
                        rightParts.append(TimeFormatters.compactTimerOnly(enteredAtMs: sub.stateEnteredAtMs, nowMs: nowMs))
                    }

                    subRow.configureSubTask(
                        state: sub.state,
                        enteredAtMs: sub.stateEnteredAtMs,
                        roleLabel: sub.roleLabel,
                        title: cleanSubTitle,
                        rightSummaryText: rightParts.joined(separator: " · "),
                        dimmedCompleted: dimCompleted
                    )
                    subRow.onClick = { [weak self] in
                        self?.onRequestClosePopover?()
                        TerminalBridge.jumpToRealWindow(sub.matchedWindow, fallbackDirectory: sub.directory)
                    }
                    sessionDocContainer.addSubview(subRow)
                    NSLayoutConstraint.activate([
                        subRow.topAnchor.constraint(
                            equalTo: previousRow?.bottomAnchor ?? sessionDocContainer.topAnchor,
                            constant: 2.0
                        ),
                        subRow.leadingAnchor.constraint(equalTo: sessionDocContainer.leadingAnchor),
                        subRow.trailingAnchor.constraint(equalTo: sessionDocContainer.trailingAnchor)
                    ])
                    previousRow = subRow
                    activeRowViews.append(subRow)
                }
            }

            if let lastRow = previousRow {
                lastRow.bottomAnchor.constraint(equalTo: sessionDocContainer.bottomAnchor, constant: -2).isActive = true
            }
        }

        // 4. 24H Sparkline Bar Chart
        sparklineView.currencyMode = currencyMode
        sparklineView.usdToCnyRate = safeRate
        sparklineView.points = scope.todayHourlySeries
    }

    private func shouldHighlightWindow(_ matched: RealTerminalWindow?, selectedWindowId: String?) -> Bool {
        guard let matched else { return false }
        if let selId = selectedWindowId {
            return matched.id == selId
        }
        return matched.isActiveTab
    }

    // MARK: - 1:1 Scrollable In-Popover Dropdown Menus (Key & Currency · Settings · Multi-Console Selector · Role Pack)

    private func dismissDropdownMenu() {
        activeDropdown = .none
        dropdownOverlay.isHidden = true
        dropdownCard.isHidden = true
    }

    private func showDropdownCard(
        kind: ActiveDropdownKind,
        sections: [[DropdownMenuItemSpec]],
        width: CGFloat,
        maxTotalHeight: CGFloat = 396,
        pinnedBackHeader: DropdownMenuItemSpec? = nil,
        anchorConstraints: [NSLayoutConstraint]
    ) {
        hoverBreakdownCard.isHidden = true
        NSLayoutConstraint.deactivate(dropdownPositionConstraints)

        dropdownCard.rebuild(
            sections: sections,
            cardWidth: width,
            maxTotalHeight: maxTotalHeight,
            pinnedBackHeader: pinnedBackHeader
        )

        NSLayoutConstraint.activate(anchorConstraints)
        dropdownPositionConstraints = anchorConstraints

        activeDropdown = kind
        dropdownCard.alphaValue = 1.0
        dropdownCard.isHidden = false
        dropdownOverlay.alphaValue = 1.0
        dropdownOverlay.isHidden = false
        view.layoutSubtreeIfNeeded()
    }

    private func toggleKeyAndCurrencyDropdown() {
        if activeDropdown == .keyAndCurrency {
            dismissDropdownMenu()
            return
        }

        let totalAllCny = lastSnapshot?.billing.spurCostCny ?? 0.0
        let allCostText = DeepSeekPricingEngine.formatMoney(
            amountCny: totalAllCny,
            mode: lastCurrencyMode,
            usdToCnyRate: lastUsdToCnyRate,
            highPrecision: totalAllCny > 0 && totalAllCny < 0.1
        )

        var scopeItems: [DropdownMenuItemSpec] = [
            DropdownMenuItemSpec(
                title: "全部 Key (汇总)",
                rightDetail: allCostText,
                rightAccent: false,
                style: lastSelectedKeyScopeId == APIKeyProfile.allKeysId ? .selected : .standard
            ) { [weak self] in
                self?.dismissDropdownMenu()
                self?.onSelectApiKeyScope?(APIKeyProfile.allKeysId)
            }
        ]

        if let scopes = lastSnapshot?.availableKeyScopes {
            for sc in scopes {
                let cText = DeepSeekPricingEngine.formatMoney(
                    amountCny: sc.billing.spurCostCny,
                    mode: lastCurrencyMode,
                    usdToCnyRate: lastUsdToCnyRate,
                    highPrecision: sc.billing.spurCostCny > 0 && sc.billing.spurCostCny < 0.1
                )
                let keyId = sc.keyId
                scopeItems.append(DropdownMenuItemSpec(
                    title: sc.title,
                    rightDetail: cText,
                    rightAccent: false,
                    style: lastSelectedKeyScopeId == keyId ? .selected : .standard
                ) { [weak self] in
                    self?.dismissDropdownMenu()
                    self?.onSelectApiKeyScope?(keyId)
                })
            }
        }

        let nextMode = lastCurrencyMode.next
        let currencyDetail = lastCurrencyMode == .cny ? "¥ CNY → $ USD" : "$ USD → ¥ CNY"
        let currencySection = [
            DropdownMenuItemSpec(
                title: "切换计费币种",
                rightDetail: currencyDetail,
                rightAccent: true,
                style: .standard
            ) { [weak self] in
                self?.dismissDropdownMenu()
                self?.onSelectCurrencyMode?(nextMode)
            }
        ]

        let manageSection = [
            DropdownMenuItemSpec(
                title: "＋ 添加 / 管理多 API-Key…",
                rightDetail: "",
                rightAccent: true,
                style: .accentAction
            ) { [weak self] in
                self?.presentApiKeyPanel()
            }
        ]

        showDropdownCard(
            kind: .keyAndCurrency,
            sections: [scopeItems, currencySection, manageSection],
            width: 274,
            maxTotalHeight: 380,
            anchorConstraints: [
                dropdownCard.topAnchor.constraint(equalTo: keySelectorCapsule.bottomAnchor, constant: 6),
                dropdownCard.trailingAnchor.constraint(equalTo: refreshCapsule.trailingAnchor)
            ]
        )
    }

    private func toggleSettingsGearDropdown() {
        if activeDropdown == .settingsGear {
            dismissDropdownMenu()
            return
        }

        let menuBarSection: [DropdownMenuItemSpec] = MenuBarDisplayMode.allCases.map { mode in
            let isSel = (mode == lastMenuBarDisplayMode)
            return DropdownMenuItemSpec(
                title: mode.settingsTitle,
                rightDetail: isSel ? "✓" : "",
                rightAccent: true,
                style: isSel ? .selected : .standard
            ) { [weak self] in
                self?.dismissDropdownMenu()
                self?.onSelectMenuBarDisplayMode?(mode)
            }
        }

        var badgeSection: [DropdownMenuItemSpec] = FloatingBadgeMode.allCases.map { bMode in
            let isSel = (bMode == lastFloatingBadgeMode)
            return DropdownMenuItemSpec(
                title: bMode.settingsTitle,
                rightDetail: isSel ? "✓" : "",
                rightAccent: true,
                style: isSel ? .selected : .standard
            ) { [weak self] in
                self?.dismissDropdownMenu()
                self?.onSelectFloatingBadgeMode?(bMode)
            }
        }

        badgeSection.append(DropdownMenuItemSpec(
            title: "开机自动启动驻留菜单栏",
            rightDetail: lastLaunchAtLoginEnabled ? "✓" : "",
            rightAccent: true,
            style: lastLaunchAtLoginEnabled ? .selected : .standard
        ) { [weak self] in
            guard let self else { return }
            let nextVal = !self.lastLaunchAtLoginEnabled
            self.dismissDropdownMenu()
            self.onToggleLaunchAtLogin?(nextVal)
        })

        let wins = lastSnapshot?.realWindows ?? []
        let consoleSummaryText: String
        if let selId = lastSelectedWindowId, let matched = wins.first(where: { $0.id == selId }) {
            consoleSummaryText = "已固定 · \(matched.shortTargetSummary) ▸"
        } else if wins.isEmpty {
            consoleSummaryText = "自动跟随 (0 个) ▸"
        } else {
            consoleSummaryText = "自动跟随 (共 \(wins.count) 个) ▸"
        }

        let focusSection: [DropdownMenuItemSpec] = [
            DropdownMenuItemSpec(
                title: "终端自动聚焦高亮",
                rightDetail: lastAutoFocusEnabled ? "✓" : "",
                rightAccent: true,
                style: .standard
            ) { [weak self] in
                guard let self else { return }
                let toggled = !self.lastAutoFocusEnabled
                self.dismissDropdownMenu()
                self.onToggleAutoFocus?(toggled)
            },
            DropdownMenuItemSpec(
                title: "选择聚焦控制台",
                rightDetail: consoleSummaryText,
                rightAccent: lastSelectedWindowId != nil,
                style: lastSelectedWindowId != nil ? .selected : .standard
            ) { [weak self] in
                self?.showConsoleSelectorDropdown()
            }
        ]

        var dataSection: [DropdownMenuItemSpec] = [
            DropdownMenuItemSpec(
                title: "管理多 API-Key 分组…",
                rightDetail: "🔑",
                rightAccent: false,
                style: .standard
            ) { [weak self] in
                self?.presentApiKeyPanel()
            },
            DropdownMenuItemSpec(
                title: "导入官方账单 CSV…",
                rightDetail: "",
                rightAccent: false,
                style: .standard
            ) { [weak self] in
                self?.dismissDropdownMenu()
                self?.handleImportCSVClick()
            }
        ]

        if lastCsvReconciliation != nil {
            dataSection.append(DropdownMenuItemSpec(
                title: "退出 CSV 对账，切回实时库",
                rightDetail: "",
                rightAccent: true,
                style: .accentAction
            ) { [weak self] in
                self?.dismissDropdownMenu()
                self?.onClearOfficialCSV?()
            })
        }

        let soundSection: [DropdownMenuItemSpec] = [
            DropdownMenuItemSpec(
                title: "发送测试通知与提示音",
                rightDetail: "🔔",
                rightAccent: false,
                style: .standard
            ) { [weak self] in
                self?.dismissDropdownMenu()
                self?.onTestNotificationSound?()
            }
        ]

        showDropdownCard(
            kind: .settingsGear,
            sections: [menuBarSection, badgeSection, focusSection, dataSection, soundSection],
            width: 304,
            maxTotalHeight: 448,
            anchorConstraints: [
                dropdownCard.topAnchor.constraint(equalTo: settingsCapsule.bottomAnchor, constant: 6),
                dropdownCard.trailingAnchor.constraint(equalTo: settingsCapsule.trailingAnchor)
            ]
        )
    }

    /// Dedicated scrollable sub-menu supporting 5, 10, or 30+ open Terminal / iTerm2 consoles without crowding the main Settings menu.
    private func showConsoleSelectorDropdown() {
        let wins = lastSnapshot?.realWindows ?? []

        let backHeader = DropdownMenuItemSpec(
            title: "‹ 返回设置菜单",
            rightDetail: "共 \(wins.count) 个控制台",
            rightAccent: false,
            style: .mutedBackHeader
        ) { [weak self] in
            self?.toggleSettingsGearDropdown()
        }

        let autoSection: [DropdownMenuItemSpec] = [
            DropdownMenuItemSpec(
                title: "跟随前台活跃终端 (自动识别)",
                rightDetail: lastSelectedWindowId == nil ? "✓" : "",
                rightAccent: true,
                style: lastSelectedWindowId == nil ? .selected : .standard
            ) { [weak self] in
                self?.dismissDropdownMenu()
                self?.onSelectRealWindowId?(nil)
            }
        ]

        let windowItems: [DropdownMenuItemSpec]
        if wins.isEmpty {
            windowItems = [
                DropdownMenuItemSpec(
                    title: "暂未检测到打开的 Terminal / iTerm2 窗口",
                    rightDetail: "",
                    rightAccent: false,
                    style: .standard
                ) { [weak self] in
                    self?.onRefreshQuota?()
                }
            ]
        } else {
            windowItems = wins.enumerated().map { idx, w in
                let wid = w.id
                let isSel = (lastSelectedWindowId == wid)
                let rightBadge = isSel ? "✓" : (w.isActiveTab ? "前台" : "")
                return DropdownMenuItemSpec(
                    title: w.indexedMenuTitle(index: idx + 1),
                    rightDetail: rightBadge,
                    rightAccent: isSel || w.isActiveTab,
                    style: isSel ? .selected : .standard
                ) { [weak self] in
                    self?.dismissDropdownMenu()
                    self?.onSelectRealWindowId?(wid)
                }
            }
        }

        let rescanSection: [DropdownMenuItemSpec] = [
            DropdownMenuItemSpec(
                title: "↻ 重新扫描本机所有控制台",
                rightDetail: "",
                rightAccent: true,
                style: .accentAction
            ) { [weak self] in
                self?.onRefreshQuota?()
            }
        ]

        showDropdownCard(
            kind: .consoleSelector,
            sections: [autoSection, windowItems, rescanSection],
            width: 356,
            maxTotalHeight: 386,
            pinnedBackHeader: backHeader,
            anchorConstraints: [
                dropdownCard.topAnchor.constraint(equalTo: settingsCapsule.bottomAnchor, constant: 6),
                dropdownCard.trailingAnchor.constraint(equalTo: settingsCapsule.trailingAnchor)
            ]
        )
    }

    private func toggleRolePackDropdown() {
        if activeDropdown == .rolePack {
            dismissDropdownMenu()
            return
        }

        let packItems: [DropdownMenuItemSpec] = lastAllPacks.map { pack in
            let pid = pack.id
            let isSel = (pid == lastActivePackId)
            return DropdownMenuItemSpec(
                title: pack.menuTitle,
                rightDetail: isSel ? "✓" : "",
                rightAccent: true,
                style: isSel ? .selected : .standard
            ) { [weak self] in
                self?.dismissDropdownMenu()
                self?.onSelectPackId?(pid)
            }
        }

        let importSection: [DropdownMenuItemSpec] = [
            DropdownMenuItemSpec(
                title: "＋ 导入自定义角色包 (.json)…",
                rightDetail: "",
                rightAccent: true,
                style: .accentAction
            ) { [weak self] in
                self?.dismissDropdownMenu()
                self?.handleImportPackClick()
            }
        ]

        showDropdownCard(
            kind: .rolePack,
            sections: [packItems, importSection],
            width: 224,
            maxTotalHeight: 340,
            anchorConstraints: [
                dropdownCard.bottomAnchor.constraint(equalTo: rolePackCapsule.topAnchor, constant: -6),
                dropdownCard.leadingAnchor.constraint(equalTo: rolePackCapsule.leadingAnchor)
            ]
        )
    }

    // MARK: - Native File Open Panels (Protected by .applicationDefined Lock)

    private func handleImportCSVClick() {
        onModalPanelStateChange?(true)
        defer {
            onModalPanelStateChange?(false)
            NSApplication.shared.activate()
            view.window?.makeKey()
        }

        let panel = NSOpenPanel()
        panel.title = "导入 DeepSeek 官方账单 CSV (可同时多选 amount-*.csv 与 cost-*.csv)"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 3)

        NSApplication.shared.activate()
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            if let parsed = DeepSeekPricingEngine.parseOfficialCSVFiles(urls: panel.urls) {
                onImportOfficialCSVs?(parsed)
            }
        }
    }

    private func handleImportPackClick() {
        onModalPanelStateChange?(true)
        defer {
            onModalPanelStateChange?(false)
            NSApplication.shared.activate()
            view.window?.makeKey()
        }

        let panel = NSOpenPanel()
        panel.title = "导入自制 DeepSeek 角色包 (.json)"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 3)

        NSApplication.shared.activate()
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(DeepSeekRolePack.self, from: data) {
            onImportCustomPack?(decoded)
        }
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - All-Spaces & Full-Screen Persistent Floating Mini Capsule (Optional Anti-Notch / Full-Screen Pin)

private final class FloatingBadgeContentView: NSView {
    var onClickBadge: (() -> Void)?
    var onOriginSaved: ((NSPoint) -> Void)?

    private let spriteView = RetinaAspectFitImageView(pointSize: 18)
    private let dotView = NSView()
    private let moneyLabel = NSTextField(labelWithString: "¥0.00")

    private var dragStartMouseScreen: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero
    private var didDragWindow = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.backgroundColor = NSColor(srgbRed: 0.985, green: 0.992, blue: 1.0, alpha: 0.96).cgColor
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor(srgbRed: 0.72, green: 0.84, blue: 0.95, alpha: 0.95).cgColor

        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 3
        dotView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dotView.widthAnchor.constraint(equalToConstant: 6),
            dotView.heightAnchor.constraint(equalToConstant: 6)
        ])

        moneyLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.2, weight: .semibold)
        moneyLabel.textColor = NSColor(srgbRed: 0.08, green: 0.13, blue: 0.22, alpha: 1.0)
        moneyLabel.lineBreakMode = .byClipping

        let stack = NSStackView(views: [spriteView, dotView, moneyLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 9, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        return super.hitTest(point) != nil ? self : nil
    }

    func update(sprite: NSImage, amountText: String, state: AgentRunState) {
        spriteView.image = sprite
        moneyLabel.stringValue = amountText
        dotView.layer?.backgroundColor = state.accentColor.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        dragStartMouseScreen = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin ?? .zero
        didDragWindow = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let win = window else { return }
        let cur = NSEvent.mouseLocation
        let dx = cur.x - dragStartMouseScreen.x
        let dy = cur.y - dragStartMouseScreen.y
        if hypot(dx, dy) > 3.0 {
            didDragWindow = true
        }
        if didDragWindow {
            win.setFrameOrigin(NSPoint(x: dragStartWindowOrigin.x + dx, y: dragStartWindowOrigin.y + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if didDragWindow {
            if let origin = window?.frame.origin {
                onOriginSaved?(origin)
            }
        } else {
            onClickBadge?()
        }
    }
}

final class FloatingStatusBadgePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private let badgeContent = FloatingBadgeContentView(frame: NSRect(x: 0, y: 0, width: 104, height: 30))

    var anchorView: NSView { badgeContent }

    var onClickBadge: (() -> Void)? {
        didSet { badgeContent.onClickBadge = onClickBadge }
    }

    var onOriginSaved: ((NSPoint) -> Void)? {
        didSet { badgeContent.onOriginSaved = onOriginSaved }
    }

    init(initialOrigin: NSPoint) {
        let rect = NSRect(origin: initialOrigin, size: NSSize(width: 104, height: 30))
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        appearance = NSAppearance(named: .aqua)
        contentView = badgeContent
    }

    func updateBadge(sprite: NSImage, amountText: String, state: AgentRunState) {
        badgeContent.update(sprite: sprite, amountText: amountText, state: state)
    }
}
