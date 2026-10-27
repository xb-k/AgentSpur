import AppKit
import Foundation
import QuartzCore
import UniformTypeIdentifiers

// MARK: - Native CoreGraphics Weekly Efficiency Line Chart View (Zero WebView)

final class NativeEfficiencyChartView: NSView {
    var points: [DailyEfficiencyPoint] = [] {
        didSet { needsDisplay = true }
    }
    var showAvgSeconds: Bool = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let bounds = self.bounds
        let bgPath = CGPath(roundedRect: bounds, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.addPath(bgPath)
        ctx.setFillColor(NSColor(srgbRed: 0.97, green: 0.985, blue: 1.0, alpha: 0.9).cgColor)
        ctx.fillPath()

        ctx.addPath(bgPath)
        ctx.setStrokeColor(NSColor(srgbRed: 0.86, green: 0.91, blue: 0.96, alpha: 1.0).cgColor)
        ctx.setLineWidth(1.0)
        ctx.strokePath()

        guard !points.isEmpty else { return }

        let leftPad: CGFloat = 30
        let rightPad: CGFloat = 14
        let bottomPad: CGFloat = 22
        let topPad: CGFloat = 16
        let plotW = max(40, bounds.width - leftPad - rightPad)
        let plotH = max(30, bounds.height - topPad - bottomPad)

        let rawValues = points.map { showAvgSeconds ? $0.avgSeconds : $0.tasksPerHour }
        let maxVal = max(rawValues.max() ?? 1.0, 1.0) * 1.18

        // 绘制虚线水平网格
        ctx.saveGState()
        ctx.setStrokeColor(NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 0.06).cgColor)
        ctx.setLineWidth(1.0)
        ctx.setLineDash(phase: 0, lengths: [3, 3])
        for i in 0...2 {
            let y = bottomPad + plotH * (CGFloat(i) / 2.0)
            ctx.move(to: CGPoint(x: leftPad, y: y))
            ctx.addLine(to: CGPoint(x: leftPad + plotW, y: y))
        }
        ctx.strokePath()
        ctx.restoreGState()

        let stepX = points.count > 1 ? plotW / CGFloat(points.count - 1) : plotW
        let coords: [CGPoint] = points.enumerated().map { idx, pt in
            let v = showAvgSeconds ? pt.avgSeconds : pt.tasksPerHour
            let x = leftPad + CGFloat(idx) * stepX
            let y = bottomPad + CGFloat(v / maxVal) * plotH
            return CGPoint(x: x, y: y)
        }

        let lineColor = showAvgSeconds
            ? NSColor(srgbRed: 0.04, green: 0.59, blue: 0.41, alpha: 1.0)
            : NSColor(srgbRed: 0.01, green: 0.52, blue: 0.78, alpha: 1.0)

        // 绘制柔和渐变面积填充
        if coords.count >= 2 {
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
            areaPath.addLine(to: CGPoint(x: coords.last!.x, y: bottomPad))
            areaPath.closeSubpath()

            ctx.saveGState()
            ctx.addPath(areaPath)
            ctx.clip()
            let cs = CGColorSpaceCreateDeviceRGB()
            let gradColors = [
                lineColor.withAlphaComponent(0.20).cgColor,
                lineColor.withAlphaComponent(0.0).cgColor
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

            // 绘制平滑折线
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
            ctx.setLineWidth(2.0)
            ctx.setLineCap(.round)
            ctx.strokePath()
        }

        // 绘制节点与日期标签
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: NSColor(srgbRed: 0.40, green: 0.46, blue: 0.55, alpha: 1.0)
        ]
        let todayAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
            .foregroundColor: lineColor
        ]

        for (idx, pt) in points.enumerated() {
            let c = coords[idx]
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - 3.0, y: c.y - 3.0, width: 6.0, height: 6.0))
            ctx.setStrokeColor(lineColor.cgColor)
            ctx.setLineWidth(1.8)
            ctx.strokeEllipse(in: CGRect(x: c.x - 3.0, y: c.y - 3.0, width: 6.0, height: 6.0))

            let str = pt.isToday ? "\(pt.dayLabel)·今" : pt.dayLabel
            let nsStr = NSString(string: str)
            let attrs = pt.isToday ? todayAttrs : labelAttrs
            let sz = nsStr.size(withAttributes: attrs)
            nsStr.draw(at: CGPoint(x: c.x - sz.width * 0.5, y: 4), withAttributes: attrs)
        }

        // 左侧最大值刻度
        let maxText = showAvgSeconds
            ? "\(Int(maxVal / 1.18))s"
            : String(format: "%.1f", maxVal / 1.18)
        NSString(string: maxText).draw(
            at: CGPoint(x: 4, y: bottomPad + plotH - 10),
            withAttributes: labelAttrs
        )
    }
}

// MARK: - Clickable Task Row Button with Blinking Auto-Focus Border Support

final class SessionRowView: NSControl {
    var onClick: (() -> Void)?
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let rightMetaField = NSTextField(labelWithString: "")
    private var isSubTaskRow = false

    init(isSubTask: Bool) {
        self.isSubTaskRow = isSubTask
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = isSubTask ? 7 : 9

        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleField.translatesAutoresizingMaskIntoConstraints = false
        rightMetaField.translatesAutoresizingMaskIntoConstraints = false

        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rightMetaField.alignment = .right
        rightMetaField.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(iconView)
        addSubview(titleField)
        addSubview(rightMetaField)

        let iconSize: CGFloat = isSubTask ? 14 : 16
        let vPad: CGFloat = isSubTask ? 5 : 7
        let hLead: CGFloat = isSubTask ? 22 : 8

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: isSubTask ? 26 : 32),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hLead),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),

            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: vPad),
            titleField.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -vPad),

            rightMetaField.leadingAnchor.constraint(greaterThanOrEqualTo: titleField.trailingAnchor, constant: 8),
            rightMetaField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            rightMetaField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        sprite: NSImage,
        title: String,
        timerText: String,
        durationSuffix: String?,
        terminalBadge: String,
        accentColor: NSColor,
        isAutoFocused: Bool,
        tooltipText: String
    ) {
        iconView.image = sprite
        self.toolTip = tooltipText

        titleField.font = NSFont.systemFont(ofSize: isSubTaskRow ? 11.5 : 12.5, weight: isAutoFocused ? .semibold : .medium)
        titleField.textColor = isAutoFocused
            ? NSColor(srgbRed: 0.03, green: 0.18, blue: 0.29, alpha: 1.0)
            : NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)
        titleField.stringValue = title

        let combined = NSMutableAttributedString()
        if let dur = durationSuffix {
            combined.append(NSAttributedString(
                string: "\(dur) · ",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular),
                    .foregroundColor: NSColor(srgbRed: 0.50, green: 0.56, blue: 0.64, alpha: 1.0)
                ]
            ))
        }
        combined.append(NSAttributedString(
            string: timerText,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium),
                .foregroundColor: accentColor
            ]
        ))
        combined.append(NSAttributedString(
            string: " · \(terminalBadge)",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10.0, weight: .regular),
                .foregroundColor: NSColor(srgbRed: 0.55, green: 0.62, blue: 0.70, alpha: 1.0)
            ]
        ))
        rightMetaField.attributedStringValue = combined

        applyFocusAppearance(isAutoFocused: isAutoFocused)
    }

    private func applyFocusAppearance(isAutoFocused: Bool) {
        guard let layer = self.layer else { return }
        layer.removeAnimation(forKey: "focusBorderBlink")

        if isAutoFocused {
            layer.backgroundColor = NSColor(srgbRed: 0.06, green: 0.65, blue: 0.91, alpha: 0.12).cgColor
            layer.borderWidth = 1.2
            let strong = NSColor(srgbRed: 0.01, green: 0.52, blue: 0.78, alpha: 0.92).cgColor
            let faint = NSColor(srgbRed: 0.06, green: 0.65, blue: 0.91, alpha: 0.18).cgColor
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
            layer.backgroundColor = NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 0.022).cgColor
            layer.borderWidth = 0
            layer.borderColor = nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor(srgbRed: 0.06, green: 0.65, blue: 0.91, alpha: 0.18).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if bounds.contains(pt) {
            onClick?()
        }
    }
}

// MARK: - Bright Minimalist Status Bar Popover Controller

final class StatusPopoverViewController: NSViewController {
    var onRefreshQuota: (() -> Void)?
    var onToggleSilentAlert: ((Bool) -> Void)?
    var onToggleAutoFocus: ((Bool) -> Void)?
    var onChangeAutoFocusTarget: ((AutoFocusWindowTarget) -> Void)?
    var onSelectPack: ((String) -> Void)?
    var onImportCustomPack: ((DeepSeekRolePack) -> Void)?
    var onConfigureApiKey: (() -> Void)?
    var onQuitApp: (() -> Void)?

    private let brandIconView = NSImageView()
    private let headerSpriteView = NSImageView()
    private let headerStatusLabel = NSTextField(labelWithString: "AgentSpur")
    private let headerSubLabel = NSTextField(labelWithString: "opencode.db · 只读")
    private let quotaInfoLabel = NSTextField(labelWithString: "")

    private let autoFocusSwitch = NSSwitch()
    private let autoFocusPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private var groupSegment: NSSegmentedControl!
    private let listStack = NSStackView()

    private let chartMetricSegment = NSSegmentedControl(labels: ["吞吐 项/时", "均耗 秒"], trackingMode: .selectOne, target: nil, action: nil)
    private let chartView = NativeEfficiencyChartView()

    private let silentSwitch = NSSwitch()
    private let packPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private var currentFilter: SessionGroupFilter = .all
    private var keyMonitor: Any?

    override func loadView() {
        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 392, height: 590))
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .aqua) // 强制明亮清透浅色视觉
        self.view = effectView

        setupLayout()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
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
        rootStack.spacing = 10
        rootStack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 12, right: 14)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: view.topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.widthAnchor.constraint(equalToConstant: 392)
        ])

        // 1. Header Row
        brandIconView.image = SpriteRenderer.renderBrandLogoImage(pointSize: 20)
        brandIconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            brandIconView.widthAnchor.constraint(equalToConstant: 20),
            brandIconView.heightAnchor.constraint(equalToConstant: 20)
        ])

        headerSpriteView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerSpriteView.widthAnchor.constraint(equalToConstant: 20),
            headerSpriteView.heightAnchor.constraint(equalToConstant: 20)
        ])

        headerStatusLabel.font = NSFont.systemFont(ofSize: 13.5, weight: .semibold)
        headerStatusLabel.textColor = NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 1.0)

        headerSubLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        headerSubLabel.textColor = NSColor(srgbRed: 0.45, green: 0.52, blue: 0.60, alpha: 1.0)

        let titleStack = NSStackView(views: [headerStatusLabel, headerSubLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 1

        let refreshBtn = makeLightButton(title: "刷新 ⌘R", tinted: false, action: #selector(handleRefreshClick))
        let keyBtn = makeLightButton(title: "额度Key", tinted: false, action: #selector(handleApiKeyClick))

        let topBar = NSStackView(views: [brandIconView, headerSpriteView, titleStack, NSView(), keyBtn, refreshBtn])
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 6
        rootStack.addArrangedSubview(topBar)

        quotaInfoLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        quotaInfoLabel.textColor = NSColor(srgbRed: 0.35, green: 0.42, blue: 0.50, alpha: 1.0)
        rootStack.addArrangedSubview(quotaInfoLabel)

        rootStack.addArrangedSubview(makeHairline())

        // 2. Terminal Auto-Focus Mode Bar
        autoFocusSwitch.controlSize = .mini
        autoFocusSwitch.target = self
        autoFocusSwitch.action = #selector(handleAutoFocusToggle)

        let autoFocusLabel = NSTextField(labelWithString: "终端自动聚焦模式")
        autoFocusLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        autoFocusLabel.textColor = NSColor(srgbRed: 0.12, green: 0.16, blue: 0.23, alpha: 1.0)

        autoFocusPopup.controlSize = .small
        autoFocusPopup.font = NSFont.systemFont(ofSize: 11)
        for item in AutoFocusWindowTarget.allCases {
            autoFocusPopup.addItem(withTitle: item.rawValue)
        }
        autoFocusPopup.target = self
        autoFocusPopup.action = #selector(handleAutoFocusTargetChange)

        let focusRow = NSStackView(views: [autoFocusSwitch, autoFocusLabel, NSView(), autoFocusPopup])
        focusRow.orientation = .horizontal
        focusRow.alignment = .centerY
        focusRow.spacing = 6
        rootStack.addArrangedSubview(focusRow)

        // 3. Session Group Filter
        groupSegment = NSSegmentedControl(
            labels: ["全部", "待处理", "运行中", "已完成"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(handleGroupSegmentChange)
        )
        groupSegment.selectedSegment = 0
        groupSegment.segmentStyle = .rounded
        groupSegment.controlSize = .small
        rootStack.addArrangedSubview(groupSegment)

        // 4. Scrollable Read-Only Session Hierarchy
        listStack.orientation = .vertical
        listStack.alignment = .width
        listStack.spacing = 5
        listStack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 235).isActive = true

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

        // 5. Weekly Efficiency Line Chart Section
        let chartTitle = NSTextField(labelWithString: "本周任务处理效率 (opencode.db)")
        chartTitle.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        chartTitle.textColor = NSColor(srgbRed: 0.12, green: 0.16, blue: 0.23, alpha: 1.0)

        chartMetricSegment.selectedSegment = 0
        chartMetricSegment.controlSize = .mini
        chartMetricSegment.target = self
        chartMetricSegment.action = #selector(handleChartMetricChange)

        let chartHeader = NSStackView(views: [chartTitle, NSView(), chartMetricSegment])
        chartHeader.orientation = .horizontal
        chartHeader.alignment = .centerY
        rootStack.addArrangedSubview(chartHeader)

        chartView.translatesAutoresizingMaskIntoConstraints = false
        chartView.heightAnchor.constraint(equalToConstant: 108).isActive = true
        rootStack.addArrangedSubview(chartView)

        rootStack.addArrangedSubview(makeHairline())

        // 6. Preferences & Role Pack Footer
        silentSwitch.controlSize = .mini
        silentSwitch.target = self
        silentSwitch.action = #selector(handleSilentSwitchToggle)

        let silentLabel = NSTextField(labelWithString: "静音通知")
        silentLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        silentLabel.textColor = NSColor(srgbRed: 0.20, green: 0.25, blue: 0.33, alpha: 1.0)

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

    // MARK: - Live State & Tick Refresh

    func renderState(
        snapshot: OpenCodeDBSnapshot,
        quota: QuotaSnapshot,
        activePack: DeepSeekRolePack,
        allPacks: [DeepSeekRolePack],
        frameIndex: Int,
        autoFocusEnabled: Bool,
        autoFocusTarget: AutoFocusWindowTarget,
        frontmostHint: FrontmostTerminalHint?,
        silentAlertEnabled: Bool
    ) {
        guard isViewLoaded else { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

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

        let activeSubCount = snapshot.masters.reduce(0) { acc, m in
            acc + m.subTasks.filter { $0.state != .completed }.count
        }
        headerSubLabel.stringValue = snapshot.dbExists
            ? "opencode.db · Master \(snapshot.masters.count) · 子任务 \(activeSubCount) 活跃"
            : "等待 ~/.local/share/opencode/opencode.db 产生会话"

        quotaInfoLabel.stringValue = "额度 \(quota.displayBalance)  ·  \(quota.resetTimeLabel)  ·  更新于 \(quota.lastRefreshedHHMM)"

        autoFocusSwitch.state = autoFocusEnabled ? .on : .off
        autoFocusPopup.isEnabled = autoFocusEnabled
        if let idx = AutoFocusWindowTarget.allCases.firstIndex(of: autoFocusTarget) {
            autoFocusPopup.selectItem(at: idx)
        }

        silentSwitch.state = silentAlertEnabled ? .on : .off

        // 同步角色下拉列表
        let titles = allPacks.map { $0.name }
        if packPopup.itemTitles != titles {
            packPopup.removeAllItems()
            packPopup.addItems(withTitles: titles)
        }
        if let pIdx = allPacks.firstIndex(where: { $0.id == activePack.id }) {
            packPopup.selectItem(at: pIdx)
        }

        let pending = snapshot.masters.filter { $0.state == .confirm }
        let running = snapshot.masters.filter { $0.state == .thinking || $0.state == .working }
        let completed = snapshot.masters.filter { $0.state == .completed || $0.state == .error }

        groupSegment.setLabel("全部 \(snapshot.masters.count)", forSegment: 0)
        groupSegment.setLabel("待处理 \(pending.count)", forSegment: 1)
        groupSegment.setLabel("运行中 \(running.count)", forSegment: 2)
        groupSegment.setLabel("已完成 \(completed.count)", forSegment: 3)

        // 重建只读分组列表
        for v in listStack.arrangedSubviews {
            listStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

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
            let gLabel = NSTextField(labelWithString: "\(groupTitle) (\(items.count))")
            gLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
            gLabel.textColor = NSColor(srgbRed: 0.50, green: 0.56, blue: 0.64, alpha: 1.0)
            listStack.addArrangedSubview(gLabel)

            if items.isEmpty {
                let empty = NSTextField(labelWithString: "  暂无会话")
                empty.font = NSFont.systemFont(ofSize: 11)
                empty.textColor = NSColor(srgbRed: 0.60, green: 0.65, blue: 0.72, alpha: 1.0)
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
                let mTimer = TimeFormatters.liveStateTimerLabel(
                    state: m.state,
                    enteredAtMs: m.stateEnteredAtMs,
                    nowMs: nowMs
                )
                let mDur = (m.state == .completed)
                    ? m.completedDurationSec.map { "总耗时 \(TimeFormatters.formatCompactSeconds($0))" }
                    : nil
                let mBadge = m.targetApp == .opencodeTUI ? "TUI" : "Tab\(m.itermTabIndex + 1)"

                row.configure(
                    sprite: mSprite,
                    title: m.title,
                    timerText: mTimer,
                    durationSuffix: mDur,
                    terminalBadge: mBadge,
                    accentColor: m.state.accentColor,
                    isAutoFocused: false,
                    tooltipText: "点击跳回 \(m.targetApp.rawValue) · opencode.db \(m.dbRecordRef)"
                )
                row.onClick = {
                    TerminalBridge.jumpToSession(
                        targetApp: m.targetApp,
                        directory: m.directory,
                        itermTabIndex: m.itermTabIndex
                    )
                }
                listStack.addArrangedSubview(row)

                for sub in m.subTasks {
                    let subRow = SessionRowView(isSubTask: true)
                    let sSprite = SpriteRenderer.renderSpriteFrame(
                        state: sub.state,
                        pack: activePack,
                        frame: frameIndex,
                        pointSize: 14
                    )
                    let sTimer = TimeFormatters.liveStateTimerLabel(
                        state: sub.state,
                        enteredAtMs: sub.stateEnteredAtMs,
                        nowMs: nowMs
                    )
                    let sDur = (sub.state == .completed)
                        ? sub.completedDurationSec.map { "耗时 \(TimeFormatters.formatCompactSeconds($0))" }
                        : nil
                    let sBadge = sub.targetApp == .opencodeTUI ? "TUI" : "Tab\(sub.itermTabIndex + 1)"
                    let matchedFocus = autoFocusEnabled && autoFocusTarget.matches(task: sub, frontmostHint: frontmostHint)

                    subRow.configure(
                        sprite: sSprite,
                        title: sub.title,
                        timerText: sTimer,
                        durationSuffix: sDur,
                        terminalBadge: sBadge,
                        accentColor: sub.state.accentColor,
                        isAutoFocused: matchedFocus,
                        tooltipText: "子任务 \(sub.roleLabel) · 点击跳回 \(sub.targetApp.rawValue) · \(sub.dbRecordRef)"
                    )
                    subRow.onClick = {
                        TerminalBridge.jumpToSession(
                            targetApp: sub.targetApp,
                            directory: sub.directory,
                            itermTabIndex: sub.itermTabIndex
                        )
                    }
                    listStack.addArrangedSubview(subRow)
                }
            }
        }

        chartView.points = snapshot.weeklySeries
    }

    // MARK: - Control Actions

    @objc private func handleRefreshClick() {
        onRefreshQuota?()
    }

    @objc private func handleApiKeyClick() {
        onConfigureApiKey?()
    }

    @objc private func handleAutoFocusToggle() {
        onToggleAutoFocus?(autoFocusSwitch.state == .on)
    }

    @objc private func handleAutoFocusTargetChange() {
        let idx = autoFocusPopup.indexOfSelectedItem
        if idx >= 0 && idx < AutoFocusWindowTarget.allCases.count {
            onChangeAutoFocusTarget?(AutoFocusWindowTarget.allCases[idx])
        }
    }

    @objc private func handleGroupSegmentChange() {
        currentFilter = SessionGroupFilter(rawValue: groupSegment.selectedSegment) ?? .all
    }

    @objc private func handleChartMetricChange() {
        chartView.showAvgSeconds = (chartMetricSegment.selectedSegment == 1)
    }

    @objc private func handleSilentSwitchToggle() {
        onToggleSilentAlert?(silentSwitch.state == .on)
    }

    @objc private func handlePackSelection() {
        let title = packPopup.titleOfSelectedItem ?? ""
        onSelectPack?(title)
    }

    @objc private func handleImportPackClick() {
        let panel = NSOpenPanel()
        panel.title = "导入自制 DeepSeek 角色包 (.json)"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

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
        v.layer?.backgroundColor = NSColor(srgbRed: 0.06, green: 0.09, blue: 0.16, alpha: 0.06).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private func makeLightButton(title: String, tinted: Bool, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .rounded
        btn.controlSize = .small
        btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        if tinted {
            btn.contentTintColor = NSColor(srgbRed: 0.01, green: 0.52, blue: 0.78, alpha: 1.0)
        }
        return btn
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
