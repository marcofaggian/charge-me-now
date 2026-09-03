import Cocoa

/// Full-screen red tint + "CHARGE ME NOW!" banner on every display.
/// The overlay is click-through so the Mac stays usable and the
/// menu-bar item remains reachable.
final class OverlayController {
    private var windows: [OverlayWindow] = []
    private var pulseTimer: Timer?

    func show(testing: Bool) {
        hide()
        for screen in NSScreen.screens {
            windows.append(OverlayWindow(screen: screen, testing: testing))
        }
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            self?.windows.forEach { ($0.contentView as? OverlayView)?.needsDisplay = true }
        }
    }

    func hide() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

final class OverlayWindow: NSWindow {
    init(screen: NSScreen, testing: Bool) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        alphaValue = 1
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        contentView = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), testing: testing)
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class OverlayView: NSView {
    private let testing: Bool
    private let startTime = Date()

    init(frame: NSRect, testing: Bool) {
        self.testing = testing
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        let elapsed = Date().timeIntervalSince(startTime)
        let pulse = 0.30 + 0.20 * (sin(elapsed * 2.6) * 0.5 + 0.5)

        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        NSColor.systemRed.withAlphaComponent(pulse).setFill()
        bounds.fill()

        drawMessage()
    }

    private func titleAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let font = NSFont(name: "Arial-Black", size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize, weight: .black)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = fontSize / 10
        shadow.shadowOffset = NSSize(width: 0, height: -fontSize / 40)

        return [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
            .shadow: shadow,
        ]
    }

    private func drawMessage() {
        let title = "CHARGE ME NOW!"

        // Fit the text to the screen.
        var fontSize = min(bounds.width / 6, bounds.height / 4)
        var attributes = titleAttributes(fontSize: fontSize)
        while NSAttributedString(string: title, attributes: attributes).size().width > bounds.width * 0.92,
              fontSize > 36 {
            fontSize *= 0.94
            attributes = titleAttributes(fontSize: fontSize)
        }

        let subtitleText = testing
            ? "TEST — stop the alarm from the ⚡ menu-bar item"
            : "Battery critically low — plug in your charger"
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(fontSize * 0.11, 22), weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.95),
            .paragraphStyle: { let p = NSMutableParagraphStyle(); p.alignment = .center; return p }(),
            .shadow: { let s = NSShadow(); s.shadowColor = NSColor.black.withAlphaComponent(0.8); s.shadowBlurRadius = 6; return s }(),
        ]

        let titleString = NSAttributedString(string: title, attributes: attributes)
        let subtitleString = NSAttributedString(string: subtitleText, attributes: subtitleAttributes)
        let titleSize = titleString.size()
        let subtitleSize = subtitleString.size()

        let gap: CGFloat = 28
        let totalHeight = titleSize.height + gap + subtitleSize.height
        let bottom = (bounds.height - totalHeight) / 2

        titleString.draw(with: NSRect(x: 0, y: bottom + subtitleSize.height + gap, width: bounds.width, height: titleSize.height))
        subtitleString.draw(with: NSRect(x: 0, y: bottom, width: bounds.width, height: subtitleSize.height))
    }
}
