import AppKit
import Foundation

enum SpriteRenderer {
    // MARK: - 15 FPS Menu Bar & Row Sprite Frame Generator

    static func renderSpriteFrame(
        state: AgentRunState,
        pack: DeepSeekRolePack,
        frame: Int,
        pointSize: CGFloat = 18
    ) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        return NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            defer { ctx.restoreGState() }

            let scale = pointSize / 18.0
            ctx.scaleBy(x: scale, y: scale)

            let phase = (Double(frame % 15) / 15.0) * (.pi * 2.0)
            let primary = NSColor.fromHex(pack.primaryColor, fallback: state.accentColor)
            let secondary = NSColor.fromHex(pack.secondaryColor, fallback: .systemTeal)

            let dy: CGFloat
            let shakeX: CGFloat
            switch state {
            case .thinking:
                dy = CGFloat(sin(phase)) * 0.9
                shakeX = 0
            case .working:
                dy = CGFloat(abs(sin(phase * 2.0))) * 1.6
                shakeX = 0
            case .confirm:
                dy = CGFloat(sin(phase * 1.5)) * 1.1
                shakeX = 0
            case .completed:
                dy = CGFloat(sin(phase * 0.5)) * 0.4
                shakeX = 0
            case .error:
                dy = 0
                shakeX = (frame % 4 < 2) ? (frame % 2 == 0 ? -1.1 : 1.1) : 0
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

            return true
        }
    }

    // MARK: - Gin · 灵动微光 (Default Fluid Droplet + State Halo)

    private static func drawGinDroplet(
        ctx: CGContext,
        state: AgentRunState,
        phase: Double,
        dx: CGFloat,
        dy: CGFloat
    ) {
        let cx: CGFloat = 9.0 + dx
        let cy: CGFloat = 8.4 + dy

        // 柔和状态微光环
        let haloRadius = 6.2 + CGFloat(sin(phase)) * 0.8
        ctx.setStrokeColor(state.accentColor.withAlphaComponent(0.28).cgColor)
        ctx.setLineWidth(1.1)
        ctx.strokeEllipse(in: CGRect(x: cx - haloRadius, y: cy - haloRadius, width: haloRadius * 2, height: haloRadius * 2))

        // 流体水滴主体
        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx, y: cy + 5.3))
        path.addCurve(
            to: CGPoint(x: cx + 4.3, y: cy - 0.8),
            control1: CGPoint(x: cx + 2.4, y: cy + 2.8),
            control2: CGPoint(x: cx + 4.3, y: cy + 1.1)
        )
        path.addArc(center: CGPoint(x: cx, y: cy - 0.8), radius: 4.3, startAngle: 0, endAngle: .pi, clockwise: true)
        path.addCurve(
            to: CGPoint(x: cx, y: cy + 5.3),
            control1: CGPoint(x: cx - 4.3, y: cy + 1.1),
            control2: CGPoint(x: cx - 2.4, y: cy + 2.8)
        )
        path.closeSubpath()

        ctx.setFillColor(state.accentColor.cgColor)
        ctx.addPath(path)
        ctx.fillPath()

        // 冰瓷高光点
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - 2.1, y: cy - 0.6, width: 1.9, height: 1.9))

        // 思考/确认状态顶部伴星点
        if state == .thinking || state == .confirm {
            let orbitAngle = CGFloat(phase)
            let ox = cx + cos(orbitAngle) * 6.3
            let oy = cy + sin(orbitAngle) * 6.3
            ctx.setFillColor(state.accentColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: ox - 1.1, y: oy - 1.1, width: 2.2, height: 2.2))
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
        ctx.setLineWidth(1.5)
        let rect = CGRect(x: 3.5 + dx, y: 3.5 + dy * 0.4, width: 11, height: 11)
        ctx.strokeEllipse(in: rect)

        let angle = (CGFloat(frame) / 15.0) * (.pi * 2.0)
        let hx = 9.0 + dx + cos(angle) * 3.4
        let hy = 9.0 + dy * 0.4 + sin(angle) * 3.4
        ctx.move(to: CGPoint(x: 9.0 + dx, y: 9.0 + dy * 0.4))
        ctx.addLine(to: CGPoint(x: hx, y: hy))
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
        ctx.setFillColor(primary.cgColor)
        ctx.fillEllipse(in: CGRect(x: 3.0 + dx, y: 5.0 + dy, width: 9.5, height: 6.5))
        let tailY = 7.5 + dy + CGFloat(sin(phase * 2.0)) * 1.4
        ctx.fillEllipse(in: CGRect(x: 11.8 + dx, y: tailY, width: 3.4, height: 2.6))
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: 5.2 + dx, y: 8.2 + dy, width: 1.5, height: 1.5))

        if state == .thinking || state == .working {
            ctx.setFillColor(secondary.cgColor)
            let spoutY = 12.2 + CGFloat((phase / (.pi * 2.0))) * 2.8
            ctx.fillEllipse(in: CGRect(x: 6.2 + dx, y: spoutY, width: 1.7, height: 1.7))
        }
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
        ctx.fill(CGRect(x: 4.5 + dx, y: 4.0 + dy, width: 9.0, height: 7.5))
        ctx.fill(CGRect(x: 4.5 + dx, y: 11.5 + dy, width: 2.4, height: 2.4))
        ctx.fill(CGRect(x: 11.1 + dx, y: 11.5 + dy, width: 2.4, height: 2.4))
        ctx.setFillColor((state == .error ? NSColor.systemRed : secondary).cgColor)
        let blink: CGFloat = (frame == 7) ? 0.6 : 1.7
        ctx.fill(CGRect(x: 6.3 + dx, y: 7.8 + dy, width: 1.7, height: blink))
        ctx.fill(CGRect(x: 10.0 + dx, y: 7.8 + dy, width: 1.7, height: blink))
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
        p.move(to: CGPoint(x: 9.0 + dx, y: 3.6 + dy))
        p.addLine(to: CGPoint(x: 14.2 + dx, y: 12.6 + dy))
        p.addLine(to: CGPoint(x: 10.8 + dx, y: 10.6 + dy))
        p.addLine(to: CGPoint(x: 7.2 + dx, y: 10.6 + dy))
        p.addLine(to: CGPoint(x: 3.8 + dx, y: 12.6 + dy))
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
                let y = offsetY + CGFloat(11 - rIdx) * cell
                ctx.fill(CGRect(x: x, y: y, width: cell, height: cell))
            }
        }
    }

    // MARK: - Brand Logo & 1024px AppIcon PNG Renderer (Used in Header & DMG Packaging)

    static func renderBrandLogoImage(pointSize: CGFloat = 20) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        return NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            drawAgentSpurEmblem(in: ctx, size: pointSize)
            return true
        }
    }

    static func exportHighResAppIconPNG(to outputPath: String, pixelSize: Int = 1024) -> Bool {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return false
        }

        NSGraphicsContext.saveGraphicsState()
        if let gfx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = gfx
            drawAgentSpurEmblem(in: gfx.cgContext, size: CGFloat(pixelSize))
        }
        NSGraphicsContext.restoreGraphicsState()

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

    private static func drawAgentSpurEmblem(in ctx: CGContext, size: CGFloat) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        let u = size / 24.0
        let pad = 1.6 * u
        let cardRect = CGRect(x: pad, y: pad, width: size - pad * 2, height: size - pad * 2)
        let corner = 5.8 * u
        let squircle = CGPath(roundedRect: cardRect, cornerWidth: corner, cornerHeight: corner, transform: nil)

        // 冰瓷浅蓝超椭圆渐变底 (#FFFFFF -> #F0F9FF -> #E0F2FE)
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
                start: CGPoint(x: cardRect.minX, y: cardRect.maxY),
                end: CGPoint(x: cardRect.maxX, y: cardRect.minY),
                options: []
            )
        }
        ctx.restoreGState()

        // 柔和天青细描边 (#BAE6FD)
        ctx.addPath(squircle)
        ctx.setStrokeColor(NSColor(srgbRed: 0.73, green: 0.90, blue: 0.99, alpha: 1.0).cgColor)
        ctx.setLineWidth(max(1.0, 0.9 * u))
        ctx.strokePath()

        // 伴星轨道弧 (Orbital Spur Arc)
        let center = CGPoint(x: 12.0 * u, y: 11.8 * u)
        ctx.setStrokeColor(NSColor(srgbRed: 0.06, green: 0.65, blue: 0.91, alpha: 0.68).cgColor)
        ctx.setLineWidth(1.45 * u)
        ctx.setLineCap(.round)
        ctx.addArc(center: center, radius: 6.6 * u, startAngle: .pi * 0.35, endAngle: .pi * 1.72, clockwise: false)
        ctx.strokePath()

        // 右上伴星子任务节点
        let satCenter = CGPoint(x: 17.55 * u, y: 15.85 * u)
        let satR = 1.45 * u
        ctx.setFillColor(NSColor(srgbRed: 0.06, green: 0.65, blue: 0.91, alpha: 1.0).cgColor)
        ctx.fillEllipse(in: CGRect(x: satCenter.x - satR, y: satCenter.y - satR, width: satR * 2, height: satR * 2))

        // 中央天青流体水滴核心 (Master Core)
        let dropPath = CGMutablePath()
        let topPt = CGPoint(x: 12.0 * u, y: 17.1 * u)
        let dropC = CGPoint(x: 12.0 * u, y: 10.65 * u)
        let dropR = 3.55 * u

        dropPath.move(to: topPt)
        dropPath.addCurve(
            to: CGPoint(x: dropC.x + dropR, y: dropC.y),
            control1: CGPoint(x: 14.1 * u, y: 14.3 * u),
            control2: CGPoint(x: dropC.x + dropR, y: dropC.y + 1.8 * u)
        )
        dropPath.addArc(center: dropC, radius: dropR, startAngle: 0, endAngle: .pi, clockwise: true)
        dropPath.addCurve(
            to: topPt,
            control1: CGPoint(x: dropC.x - dropR, y: dropC.y + 1.8 * u),
            control2: CGPoint(x: 9.9 * u, y: 14.3 * u)
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
                start: CGPoint(x: 12.0 * u, y: 17.1 * u),
                end: CGPoint(x: 12.0 * u, y: 7.1 * u),
                options: []
            )
        }
        ctx.restoreGState()

        // 冰瓷透亮高光
        let hlR = 1.02 * u
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.fillEllipse(in: CGRect(x: 10.85 * u - hlR, y: 11.25 * u - hlR, width: hlR * 2, height: hlR * 2))
    }
}
