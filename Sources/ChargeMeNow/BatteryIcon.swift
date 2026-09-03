import Cocoa

/// Custom-drawn battery state-of-charge icon for the menu bar.
///
/// The SoC fill advances in 10 % increments (rounded to the nearest 10 %)
/// and is drawn over the bezel, hiding the border under the color — a full
/// battery reads as one solid green shape. Below 10 % the fill is red while
/// discharging; while charging the fill is always green with a white bolt
/// (dark halo) on top.
enum BatteryIcon {
    static let canvas = NSSize(width: 24, height: 20)

    private static var cache: [String: NSImage] = [:]

    static func image(percent: Int, charging: Bool) -> NSImage {
        let fraction = fillFraction(for: percent)
        let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua, .vibrantDark]) == .darkAqua
        let key = "\(Int((fraction * 100).rounded()))-\(charging)-\(isDark)"
        if let cached = cache[key] {
            return cached
        }

        // Adapt the outline to light/dark menu bars.
        let outline = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantDark]) == .darkAqua {
                return NSColor.white
            }
            return NSColor.black
        }
        let image = NSImage(size: canvas)
        image.lockFocusFlipped(true)
        drawBattery(in: NSRect(origin: .zero, size: canvas),
                    percent: percent,
                    charging: charging,
                    outline: outline)
        image.unlockFocus()
        image.isTemplate = false
        cache[key] = image
        return image
    }

    // MARK: - Drawing (expects a flipped context)

    static func drawBattery(in rect: CGRect, percent: Int, charging: Bool, outline: NSColor) {
        let stroke: CGFloat = 1.2
        let bodyHeight = rect.height * 0.55
        let bodyRect = CGRect(x: rect.minX + 1,
                              y: rect.midY - bodyHeight / 2,
                              width: rect.width * 0.835,
                              height: bodyHeight)

        // Body border — 50 % transparent; the SoC fill covers it where present.
        let border = outline.withAlphaComponent(0.5)
        let body = NSBezierPath(roundedRect: bodyRect, xRadius: 2.4, yRadius: 2.4)
        body.lineWidth = stroke
        border.setStroke()
        body.stroke()

        // Terminal nub
        let nubHeight = bodyHeight * 0.42
        let nub = NSBezierPath(roundedRect: CGRect(x: bodyRect.maxX + 0.8,
                                                   y: rect.midY - nubHeight / 2,
                                                   width: 2.0,
                                                   height: nubHeight),
                               xRadius: 0.7, yRadius: 0.7)
        border.setFill()
        nub.fill()

        // SoC fill — drawn on top of the bezel, covering the border with
        // color; only the unfilled portion keeps a visible outline.
        let outer = bodyRect.insetBy(dx: -stroke / 2, dy: -stroke / 2)
        let fraction = fillFraction(for: percent)
        if fraction > 0.02, outer.width > 1, outer.height > 0.5 {
            let width = min(max(outer.width * fraction, 2.4), outer.width)
            let fill = NSBezierPath(roundedRect: CGRect(x: outer.minX, y: outer.minY,
                                                        width: width, height: outer.height),
                                    xRadius: 3.0, yRadius: 3.0)
            fillColor(percent: percent, charging: charging).setFill()
            fill.fill()
        }

        if charging {
            drawBolt(inside: bodyRect)
        }
    }

    /// SoC in 10 % increments, rounded to the nearest 10 %.
    private static func fillFraction(for percent: Int) -> Double {
        let steps = (Double(percent) / 10.0).rounded() / 10.0
        guard steps > 0 else { return percent > 0 ? 0.08 : 0 }
        return min(max(steps, 0.10), 1.0)
    }

    private static func fillColor(percent: Int, charging: Bool) -> NSColor {
        if !charging && percent < 10 {
            return .systemRed
        }
        return .systemGreen
    }

    /// Lightning bolt with a dark halo so it reads on any fill color.
    /// Like the SoC fill, it goes over the battery's edges — extending
    /// past the top and bottom borders.
    private static func drawBolt(inside bodyRect: CGRect) {
        let unitPoints: [(CGFloat, CGFloat)] = [
            (0.58, 0.02), (0.25, 0.55), (0.45, 0.55),
            (0.40, 0.98), (0.75, 0.42), (0.54, 0.42),
        ]
        let width = bodyRect.width * 0.70
        let height = bodyRect.height * 1.45
        func boltPath(scale: CGFloat) -> NSBezierPath {
            let scaledWidth = width * scale
            let scaledHeight = height * scale
            let scaledOriginX = bodyRect.midX - scaledWidth / 2
            let scaledOriginY = bodyRect.midY - scaledHeight / 2
            let path = NSBezierPath()
            for (index, point) in unitPoints.enumerated() {
                let x = scaledOriginX + point.0 * scaledWidth
                let y = scaledOriginY + point.1 * scaledHeight
                if index == 0 {
                    path.move(to: NSPoint(x: x, y: y))
                } else {
                    path.line(to: NSPoint(x: x, y: y))
                }
            }
            path.close()
            return path
        }
        NSColor.black.setFill()
        boltPath(scale: 1.18).fill()
        NSColor.white.setFill()
        boltPath(scale: 1.0).fill()
    }
}
