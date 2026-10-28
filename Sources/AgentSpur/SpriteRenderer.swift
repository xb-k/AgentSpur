import AppKit
import Foundation
import SwiftUI

// MARK: - SwiftUI Retina Aspect-Fit Image Rendering Components

/// SwiftUI 状态精灵图标组件：强制 `.aspectRatio(contentMode: .fit)` 与居中对齐，确保在 @2x/@3x Retina 屏幕下绝不拉伸变形
struct StatusSpriteImageView: View {
    let state: AgentRunState
    let pack: DeepSeekRolePack
    let frame: Int
    var pointSize: CGFloat = 18

    var body: some View {
        Image(
            nsImage: SpriteRenderer.renderSpriteFrame(
                state: state,
                pack: pack,
                frame: frame,
                pointSize: pointSize
            )
        )
        .interpolation(.high)
        .antialiased(true)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: pointSize, height: pointSize, alignment: .center)
    }
}

/// SwiftUI 品牌徽标渲染组件：强制 `.aspectRatio(contentMode: .fit)` 与 1:1 居中约束，适配 Retina 高分屏
struct BrandLogoImageView: View {
    var pointSize: CGFloat = 22

    var body: some View {
        Image(nsImage: SpriteRenderer.renderBrandLogoImage(pointSize: pointSize))
            .interpolation(.high)
            .antialiased(true)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: pointSize, height: pointSize, alignment: .center)
    }
}

// MARK: - AppKit Retina-Aware Centered Aspect-Fit Icon View (Zero Layer-Stretch)

/// AppKit 专用 1:1 等比居中图标视图：直接重写 `draw(_:)` 按 `centeredAspectFitSquare` 绘制，彻底杜绝 NSImageView Layer 拉伸压缩
final class RetinaAspectFitImageView: NSView {
    private let lockedPointSize: CGFloat

    var image: NSImage? {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    init(pointSize: CGFloat) {
        self.lockedPointSize = pointSize
        super.init(frame: NSRect(x: 0, y: 0, width: pointSize, height: pointSize))
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        translatesAutoresizingMaskIntoConstraints = false

        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)

        let w = widthAnchor.constraint(equalToConstant: pointSize)
        let h = heightAnchor.constraint(equalToConstant: pointSize)
        w.priority = .required
        h.priority = .required
        NSLayoutConstraint.activate([w, h])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: lockedPointSize, height: lockedPointSize)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let img = image else { return }
        let fitRect = SpriteRenderer.centeredAspectFitSquare(in: bounds)
        guard fitRect.width > 0 else { return }
        NSGraphicsContext.current?.imageInterpolation = .high
        img.draw(
            in: fitRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: true,
            hints: nil
        )
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncRetinaBackingScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncRetinaBackingScale()
    }

    private func syncRetinaBackingScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        layer?.contentsScale = scale
        needsDisplay = true
    }
}

// MARK: - Core Vector & Pixel Sprite Renderer (Retina @2x/@3x Multi-Scale + Strict Aspect-Fit)

enum SpriteRenderer {
    /// 计算在任意目标矩形内的严格 1:1 居中 Aspect-Fit 正方形区域，防止非等比容器导致图标拉伸
    static func centeredAspectFitSquare(in rect: NSRect) -> NSRect {
        guard rect.width > 0, rect.height > 0 else { return .zero }
        let side = min(rect.width, rect.height)
        let originX = rect.minX + (rect.width - side) * 0.5
        let originY = rect.minY + (rect.height - side) * 0.5
        return NSRect(x: originX, y: originY, width: side, height: side)
    }

    /// 包装 SwiftUI `.aspectRatio(contentMode: .fit)` 状态图标为原生 NSView（可用于任意混合容器）
    static func makeHostedStatusSpriteView(
        state: AgentRunState,
        pack: DeepSeekRolePack,
        frame: Int,
        pointSize: CGFloat = 18
    ) -> NSHostingView<StatusSpriteImageView> {
        let host = NSHostingView(
            rootView: StatusSpriteImageView(
                state: state,
                pack: pack,
                frame: frame,
                pointSize: pointSize
            )
        )
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.widthAnchor.constraint(equalToConstant: pointSize),
            host.heightAnchor.constraint(equalToConstant: pointSize)
        ])
        return host
    }

    /// 包装 SwiftUI `.aspectRatio(contentMode: .fit)` 品牌徽标为原生 NSView
    static func makeHostedBrandLogoView(pointSize: CGFloat = 22) -> NSHostingView<BrandLogoImageView> {
        let host = NSHostingView(rootView: BrandLogoImageView(pointSize: pointSize))
        host.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.widthAnchor.constraint(equalToConstant: pointSize),
            host.heightAnchor.constraint(equalToConstant: pointSize)
        ])
        return host
    }

    // MARK: - 15 FPS Menu Bar & Row Sprite Frame Generator (Retina-Dynamic NSCustomImageRep)

    static func renderSpriteFrame(
        state: AgentRunState,
        pack: DeepSeekRolePack,
        frame: Int,
        pointSize: CGFloat = 18,
        showStatusDot: Bool = false
    ) -> NSImage {
        let safePointSize = max(12, pointSize)
        let size = NSSize(width: safePointSize, height: safePointSize)

        // NSCustomImageRep 会在 @1x / @2x / @3x Retina 下由系统按真实设备分辨率实时回调此闭包；
        // 使用 centeredAspectFitSquare(in: dstRect) 严格执行等比居中（等价于 .aspectRatio(contentMode: .fit)）
        let img = NSImage(size: size, flipped: true) { dstRect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let fitRect = centeredAspectFitSquare(in: dstRect)
            guard fitRect.width > 0 else { return false }

            ctx.saveGState()
            defer { ctx.restoreGState() }

            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            ctx.interpolationQuality = .high

            // 平移至居中正方形原点，并按 18x18 基准网格做严格 X=Y 等比缩放
            ctx.translateBy(x: fitRect.minX, y: fitRect.minY)
            let uniformScale = fitRect.width / 18.0
            ctx.scaleBy(x: uniformScale, y: uniformScale)

            let phase = (Double(frame % 15) / 15.0) * (.pi * 2.0)
            let primary = NSColor.fromHex(pack.primaryColor, fallback: state.accentColor)
            let secondary = NSColor.fromHex(pack.secondaryColor, fallback: .systemTeal)

            let dy: CGFloat
            let shakeX: CGFloat
            switch state {
            case .thinking:
                dy = -CGFloat(sin(phase)) * 0.85
                shakeX = 0
            case .working:
                dy = -CGFloat(abs(sin(phase * 2.0))) * 1.35
                shakeX = 0
            case .confirm:
                dy = -CGFloat(sin(phase * 1.5)) * 0.95
                shakeX = 0
            case .completed:
                dy = -CGFloat(sin(phase * 0.5)) * 0.30
                shakeX = 0
            case .error:
                dy = 0
                shakeX = (frame % 4 < 2) ? (frame % 2 == 0 ? -1.0 : 1.0) : 0
            }

            switch pack.archetype {
            case .customPixel:
                drawCustomPixelMatrix(
                    ctx: ctx,
                    rows: pack.customBaseSprite ?? [],
                    primary: primary,
                    secondary: secondary,
                    dx: shakeX,
                    dy: dy
                )
            case .glyph:
                drawAppKitGlyph(ctx: ctx, state: state, frame: frame, dx: shakeX, dy: dy)
            case .whale:
                drawMiniWhale(ctx: ctx, state: state, primary: primary, secondary: secondary, phase: phase, dx: shakeX, dy: dy)
            case .neko:
                drawPixelNeko(ctx: ctx, state: state, primary: primary, secondary: secondary, frame: frame, dx: shakeX, dy: dy)
            case .kitsune:
                drawOrigamiKitsune(ctx: ctx, state: state, primary: primary, secondary: secondary, dy: dy, dx: shakeX)
            case .droplet:
                drawGinDroplet(ctx: ctx, state: state, phase: phase, dx: shakeX, dy: dy)
            }

            // 紧凑仅图标模式下，在右下角绘制高对比度白边实时状态微点（无论深浅壁纸菜单栏均清晰可辨）
            if showStatusDot && state != .completed {
                let dotCenter = CGPoint(x: 15.1, y: 15.1)
                let outerR: CGFloat = 2.65
                let innerR: CGFloat = 1.85
                ctx.setFillColor(NSColor.white.withAlphaComponent(0.96).cgColor)
                ctx.fillEllipse(in: CGRect(x: dotCenter.x - outerR, y: dotCenter.y - outerR, width: outerR * 2, height: outerR * 2))
                ctx.setFillColor(state.accentColor.cgColor)
                ctx.fillEllipse(in: CGRect(x: dotCenter.x - innerR, y: dotCenter.y - innerR, width: innerR * 2, height: innerR * 2))
            }

            return true
        }
        img.isTemplate = false
        return img
    }

    // MARK: - Gin · 灵动微光 (Flipped 18x18 Top-Left Origin, Pure Bezier Fluid Droplet)

    private static func drawGinDroplet(
        ctx: CGContext,
        state: AgentRunState,
        phase: Double,
        dx: CGFloat,
        dy: CGFloat
    ) {
        let cx: CGFloat = 9.0 + dx
        let cy: CGFloat = 9.2 + dy

        // 柔和状态微光环
        let haloRadius = 6.3 + CGFloat(sin(phase)) * 0.65
        ctx.setStrokeColor(state.accentColor.withAlphaComponent(0.24).cgColor)
        ctx.setLineWidth(1.05)
        ctx.strokeEllipse(in: CGRect(x: cx - haloRadius, y: cy - haloRadius, width: haloRadius * 2, height: haloRadius * 2))

        // 纯三次贝塞尔水滴（尖端朝上 y=cy-5.2，圆润底部 y=cy+4.45，跨坐标系零翻转误差）
        let topY = cy - 5.2
        let midY = cy + 0.85
        let botY = cy + 4.45
        let r: CGFloat = 3.65

        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx, y: topY))
        path.addCurve(
            to: CGPoint(x: cx + r, y: midY),
            control1: CGPoint(x: cx + 1.9, y: topY + 2.3),
            control2: CGPoint(x: cx + r, y: midY - 1.7)
        )
        path.addCurve(
            to: CGPoint(x: cx, y: botY),
            control1: CGPoint(x: cx + r, y: midY + 2.02),
            control2: CGPoint(x: cx + 2.02, y: botY)
        )
        path.addCurve(
            to: CGPoint(x: cx - r, y: midY),
            control1: CGPoint(x: cx - 2.02, y: botY),
            control2: CGPoint(x: cx - r, y: midY + 2.02)
        )
        path.addCurve(
            to: CGPoint(x: cx, y: topY),
            control1: CGPoint(x: cx - r, y: midY - 1.7),
            control2: CGPoint(x: cx - 1.9, y: topY + 2.3)
        )
        path.closeSubpath()

        ctx.setFillColor(state.accentColor.cgColor)
        ctx.addPath(path)
        ctx.fillPath()

        // 冰瓷高光点
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - 2.0, y: cy - 0.5, width: 1.75, height: 1.75))

        // 思考/确认状态伴星节点
        if state == .thinking || state == .confirm {
            let orbitAngle = CGFloat(phase) - .pi * 0.5
            let ox = cx + cos(orbitAngle) * 6.3
            let oy = cy + sin(orbitAngle) * 6.3
            ctx.setFillColor(state.accentColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: ox - 1.15, y: oy - 1.15, width: 2.3, height: 2.3))
        }
    }

    private static func drawAppKitGlyph(
        ctx: CGContext,
        state: AgentRunState,
        frame: Int,
        dx: CGFloat,
        dy: CGFloat
    ) {
        let c = state.accentColor
        ctx.setStrokeColor(c.cgColor)
        ctx.setLineWidth(1.45)
        let rect = CGRect(x: 3.5 + dx, y: 3.5 + dy * 0.4, width: 11, height: 11)
        ctx.strokeEllipse(in: rect)

        let angle = (CGFloat(frame) / 15.0) * (.pi * 2.0) - (.pi * 0.5)
        let hx = 9.0 + dx + cos(angle) * 3.4
        let hy = 9.0 + dy * 0.4 + sin(angle) * 3.4
        ctx.move(to: CGPoint(x: 9.0 + dx, y: 9.0 + dy * 0.4))
        ctx.addLine(to: CGPoint(x: hx, y: hy))
        ctx.setLineCap(.round)
        ctx.strokePath()
    }

    private static func drawMiniWhale(
        ctx: CGContext,
        state: AgentRunState,
        primary: NSColor,
        secondary: NSColor,
        phase: Double,
        dx: CGFloat,
        dy: CGFloat
    ) {
        // 饱满圆润 1:1 比例小鲸鱼 (18x18 翻转坐标系: (0,0)=左上角，视觉包围盒约 14.4 x 13.4，绝不扁平压缩)
        let bodyColor: NSColor = (state == .error)
            ? NSColor(srgbRed: 0.88, green: 0.24, blue: 0.28, alpha: 1.0)
            : primary
        let accentSpoutColor: NSColor = (state == .error)
            ? NSColor(srgbRed: 0.96, green: 0.45, blue: 0.45, alpha: 1.0)
            : secondary

        let tailSwing = CGFloat(sin(phase * 2.0)) * (state.isActiveRunning ? 0.95 : 0.25)
        let bx = dx
        let by = dy * 0.55

        // 1. 头顶灵动双水柱水珠 (全状态保留饱满高度比例，运行态轻盈跃动)
        let spoutLift = state.isActiveRunning ? CGFloat(abs(sin(phase))) * 0.9 : 0.0
        ctx.setFillColor(accentSpoutColor.withAlphaComponent(0.92).cgColor)
        ctx.fillEllipse(in: CGRect(x: 4.5 + bx, y: 2.1 - spoutLift + by, width: 1.75, height: 1.75))
        ctx.fillEllipse(in: CGRect(x: 7.1 + bx, y: 2.5 - spoutLift * 0.7 + by, width: 1.45, height: 1.45))

        // 2. 圆润高额头鲸身 + 上扬分叉尾鳍一体化贝塞尔轮廓
        let whalePath = CGMutablePath()
        // 从圆润吻部左端起笔
        whalePath.move(to: CGPoint(x: 1.8 + bx, y: 10.6 + by))
        // 高耸圆润额头拱顶 (打造可爱饱满头部，告别扁平椭圆)
        whalePath.addCurve(
            to: CGPoint(x: 7.4 + bx, y: 4.8 + by),
            control1: CGPoint(x: 1.7 + bx, y: 6.2 + by),
            control2: CGPoint(x: 4.1 + bx, y: 4.7 + by)
        )
        // 背部流畅收窄至尾柄
        whalePath.addCurve(
            to: CGPoint(x: 12.6 + bx, y: 10.1 + by + tailSwing * 0.35),
            control1: CGPoint(x: 10.3 + bx, y: 4.9 + by),
            control2: CGPoint(x: 11.6 + bx, y: 8.8 + by)
        )
        // 上扬分叉尾鳍（上叶）
        whalePath.addCurve(
            to: CGPoint(x: 16.1 + bx, y: 6.5 + by + tailSwing),
            control1: CGPoint(x: 13.6 + bx, y: 8.4 + by + tailSwing * 0.6),
            control2: CGPoint(x: 14.9 + bx, y: 6.4 + by + tailSwing)
        )
        // 尾鳍V形内凹中心点
        whalePath.addCurve(
            to: CGPoint(x: 14.4 + bx, y: 10.3 + by + tailSwing * 0.6),
            control1: CGPoint(x: 16.0 + bx, y: 8.3 + by + tailSwing * 0.8),
            control2: CGPoint(x: 15.1 + bx, y: 9.6 + by + tailSwing * 0.6)
        )
        // 分叉尾鳍（下叶）
        whalePath.addCurve(
            to: CGPoint(x: 16.2 + bx, y: 13.2 + by + tailSwing),
            control1: CGPoint(x: 15.3 + bx, y: 10.9 + by + tailSwing * 0.7),
            control2: CGPoint(x: 16.3 + bx, y: 11.9 + by + tailSwing)
        )
        // 尾柄下沿收回圆润腹部
        whalePath.addCurve(
            to: CGPoint(x: 12.1 + bx, y: 12.3 + by + tailSwing * 0.25),
            control1: CGPoint(x: 14.9 + bx, y: 13.4 + by + tailSwing * 0.7),
            control2: CGPoint(x: 13.4 + bx, y: 12.7 + by + tailSwing * 0.4)
        )
        // 饱满圆弧大肚皮回到吻部
        whalePath.addCurve(
            to: CGPoint(x: 1.8 + bx, y: 10.6 + by),
            control1: CGPoint(x: 10.2 + bx, y: 15.3 + by),
            control2: CGPoint(x: 2.2 + bx, y: 14.9 + by)
        )
        whalePath.closeSubpath()

        ctx.setFillColor(bodyColor.cgColor)
        ctx.addPath(whalePath)
        ctx.fillPath()

        // 3. 冰瓷浅白肚皮弧面（裁剪在鲸身内部，提升立体辨识度）
        ctx.saveGState()
        ctx.addPath(whalePath)
        ctx.clip()
        let bellyPath = CGMutablePath()
        bellyPath.move(to: CGPoint(x: 1.6 + bx, y: 11.4 + by))
        bellyPath.addQuadCurve(
            to: CGPoint(x: 10.6 + bx, y: 13.4 + by),
            control: CGPoint(x: 6.2 + bx, y: 11.6 + by)
        )
        bellyPath.addLine(to: CGPoint(x: 10.6 + bx, y: 16.0 + by))
        bellyPath.addLine(to: CGPoint(x: 1.6 + bx, y: 16.0 + by))
        bellyPath.closeSubpath()
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.78).cgColor)
        ctx.addPath(bellyPath)
        ctx.fillPath()
        ctx.restoreGState()

        // 4. 明亮圆眼睛与高光瞳孔
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: 4.3 + bx, y: 7.8 + by, width: 2.5, height: 2.5))
        ctx.setFillColor(NSColor(srgbRed: 0.06, green: 0.12, blue: 0.24, alpha: 1.0).cgColor)
        ctx.fillEllipse(in: CGRect(x: 4.95 + bx, y: 8.35 + by, width: 1.35, height: 1.35))
    }

    private static func drawPixelNeko(
        ctx: CGContext,
        state: AgentRunState,
        primary: NSColor,
        secondary: NSColor,
        frame: Int,
        dx: CGFloat,
        dy: CGFloat
    ) {
        ctx.setFillColor(primary.cgColor)
        ctx.fill(CGRect(x: 4.4 + dx, y: 4.0 + dy, width: 2.4, height: 2.4))
        ctx.fill(CGRect(x: 11.2 + dx, y: 4.0 + dy, width: 2.4, height: 2.4))
        ctx.fill(CGRect(x: 4.4 + dx, y: 6.2 + dy, width: 9.2, height: 7.4))

        ctx.setFillColor((state == .error ? NSColor.systemRed : secondary).cgColor)
        let blink: CGFloat = (frame == 7) ? 0.65 : 1.75
        let eyeY: CGFloat = (frame == 7) ? (9.5 + dy) : (8.9 + dy)
        ctx.fill(CGRect(x: 6.2 + dx, y: eyeY, width: 1.75, height: blink))
        ctx.fill(CGRect(x: 10.05 + dx, y: eyeY, width: 1.75, height: blink))
    }

    private static func drawOrigamiKitsune(
        ctx: CGContext,
        state: AgentRunState,
        primary: NSColor,
        secondary: NSColor,
        dy: CGFloat,
        dx: CGFloat
    ) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 9.0 + dx, y: 14.3 + dy))
        p.addLine(to: CGPoint(x: 14.2 + dx, y: 5.2 + dy))
        p.addLine(to: CGPoint(x: 10.8 + dx, y: 7.4 + dy))
        p.addLine(to: CGPoint(x: 7.2 + dx, y: 7.4 + dy))
        p.addLine(to: CGPoint(x: 3.8 + dx, y: 5.2 + dy))
        p.closeSubpath()
        ctx.setFillColor((state == .confirm ? secondary : primary).cgColor)
        ctx.addPath(p)
        ctx.fillPath()
    }

    private static func drawCustomPixelMatrix(
        ctx: CGContext,
        rows: [String],
        primary: NSColor,
        secondary: NSColor,
        dx: CGFloat,
        dy: CGFloat
    ) {
        let cell: CGFloat = 1.25
        let offsetX: CGFloat = 1.5 + dx
        let offsetY: CGFloat = 1.5 + dy
        for (rIdx, row) in rows.prefix(12).enumerated() {
            for (cIdx, ch) in row.prefix(12).enumerated() {
                if ch == "." { continue }
                ctx.setFillColor((ch == "+" ? secondary : primary).cgColor)
                let x = offsetX + CGFloat(cIdx) * cell
                let y = offsetY + CGFloat(rIdx) * cell
                ctx.fill(CGRect(x: x, y: y, width: cell, height: cell))
            }
        }
    }

    // MARK: - Brand Logo & 1024px AppIcon PNG Renderer (Retina-Dynamic + Centered 1:1 Aspect-Fit)

    static func renderBrandLogoImage(pointSize: CGFloat = 22) -> NSImage {
        let safePointSize = max(14, pointSize)
        let size = NSSize(width: safePointSize, height: safePointSize)
        let img = NSImage(size: size, flipped: true) { dstRect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let fitRect = centeredAspectFitSquare(in: dstRect)
            guard fitRect.width > 0 else { return false }

            ctx.saveGState()
            defer { ctx.restoreGState() }
            ctx.translateBy(x: fitRect.minX, y: fitRect.minY)
            drawAgentSpurEmblemTopLeftOrigin(in: ctx, size: fitRect.width)
            return true
        }
        img.isTemplate = false
        return img
    }

    static func exportHighResAppIconPNG(to outputPath: String, pixelSize: Int = 1024) -> Bool {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }

        let sz = CGFloat(pixelSize)
        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: sz)
        ctx.scaleBy(x: 1, y: -1)
        drawAgentSpurEmblemTopLeftOrigin(in: ctx, size: sz)
        ctx.restoreGState()

        guard let cgImage = ctx.makeImage() else {
            return false
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try pngData.write(to: URL(fileURLWithPath: outputPath))
            return true
        } catch {
            return false
        }
    }

    /// 在 (0,0)=左上角、24x24 等比基准网格中绘制 AgentSpur 品牌徽标，与 SVG 矢量曲线 100% 对齐
    private static func drawAgentSpurEmblemTopLeftOrigin(in ctx: CGContext, size: CGFloat) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high

        let u = size / 24.0
        let pad = 1.5 * u
        let cardRect = CGRect(x: pad, y: pad, width: 21.0 * u, height: 21.0 * u)
        let corner = 6.0 * u
        let squircle = CGPath(roundedRect: cardRect, cornerWidth: corner, cornerHeight: corner, transform: nil)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bgColors = [
            NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1.0).cgColor,
            NSColor(srgbRed: 0.94, green: 0.98, blue: 1.00, alpha: 1.0).cgColor,
            NSColor(srgbRed: 0.88, green: 0.95, blue: 1.00, alpha: 1.0).cgColor
        ] as CFArray
        let bgLocs: [CGFloat] = [0.0, 0.55, 1.0]

        ctx.saveGState()
        ctx.addPath(squircle)
        ctx.clip()
        if let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocs) {
            ctx.drawLinearGradient(
                bgGrad,
                start: CGPoint(x: 2.0 * u, y: 2.0 * u),
                end: CGPoint(x: 22.0 * u, y: 22.0 * u),
                options: []
            )
        }
        ctx.restoreGState()

        // 柔和冰瓷细描边 (#BAE6FD)
        ctx.addPath(squircle)
        ctx.setStrokeColor(NSColor(srgbRed: 0.73, green: 0.90, blue: 0.99, alpha: 1.0).cgColor)
        ctx.setLineWidth(max(0.9, 1.0 * u))
        ctx.strokePath()

        // 伴星轨道弧 (参数方程精确采样 SVG: M5.9 14.5 A6.75 6.75 0 1 1 15.8 17.55)
        let orbitPath = CGMutablePath()
        let cx = 12.0 * u
        let cy = 12.0 * u
        let orbitR = 6.75 * u
        let startAngle: CGFloat = 2.752
        let totalSweep: CGFloat = 4.501
        let steps = 40
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let ang = startAngle + t * totalSweep
            let px = cx + orbitR * cos(ang)
            let py = cy + orbitR * sin(ang)
            if i == 0 {
                orbitPath.move(to: CGPoint(x: px, y: py))
            } else {
                orbitPath.addLine(to: CGPoint(x: px, y: py))
            }
        }
        ctx.addPath(orbitPath)
        ctx.setStrokeColor(NSColor(srgbRed: 0.06, green: 0.65, blue: 0.91, alpha: 0.76).cgColor)
        ctx.setLineWidth(1.45 * u)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()

        // 右上伴星子任务节点 (cx=17.65, cy=8.15, r=1.4)
        let satCenter = CGPoint(x: 17.65 * u, y: 8.15 * u)
        let satR = 1.40 * u
        ctx.setFillColor(NSColor(srgbRed: 0.06, green: 0.65, blue: 0.91, alpha: 1.0).cgColor)
        ctx.fillEllipse(in: CGRect(x: satCenter.x - satR, y: satCenter.y - satR, width: satR * 2, height: satR * 2))

        // 中央天青流体水滴核心
        let dropPath = CGMutablePath()
        dropPath.move(to: CGPoint(x: 12.0 * u, y: 6.9 * u))
        dropPath.addCurve(
            to: CGPoint(x: 15.45 * u, y: 13.15 * u),
            control1: CGPoint(x: 13.65 * u, y: 8.65 * u),
            control2: CGPoint(x: 15.45 * u, y: 11.20 * u)
        )
        dropPath.addCurve(
            to: CGPoint(x: 12.0 * u, y: 16.65 * u),
            control1: CGPoint(x: 15.45 * u, y: 15.08 * u),
            control2: CGPoint(x: 13.90 * u, y: 16.65 * u)
        )
        dropPath.addCurve(
            to: CGPoint(x: 8.55 * u, y: 13.15 * u),
            control1: CGPoint(x: 10.10 * u, y: 16.65 * u),
            control2: CGPoint(x: 8.55 * u, y: 15.08 * u)
        )
        dropPath.addCurve(
            to: CGPoint(x: 12.0 * u, y: 6.9 * u),
            control1: CGPoint(x: 8.55 * u, y: 11.20 * u),
            control2: CGPoint(x: 10.35 * u, y: 8.65 * u)
        )
        dropPath.closeSubpath()

        ctx.saveGState()
        ctx.addPath(dropPath)
        ctx.clip()
        let coreColors = [
            NSColor(srgbRed: 0.22, green: 0.74, blue: 0.97, alpha: 1.0).cgColor,
            NSColor(srgbRed: 0.01, green: 0.52, blue: 0.78, alpha: 1.0).cgColor
        ] as CFArray
        if let coreGrad = CGGradient(colorsSpace: colorSpace, colors: coreColors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(
                coreGrad,
                start: CGPoint(x: 9.0 * u, y: 6.9 * u),
                end: CGPoint(x: 15.5 * u, y: 16.65 * u),
                options: []
            )
        }
        ctx.restoreGState()

        // 冰瓷透亮高光点
        let hlR = 0.98 * u
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
        ctx.fillEllipse(in: CGRect(x: 10.95 * u - hlR, y: 12.55 * u - hlR, width: hlR * 2, height: hlR * 2))
    }
}
