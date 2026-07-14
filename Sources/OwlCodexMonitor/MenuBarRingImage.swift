import AppKit

@MainActor
enum MenuBarRingImage {
    static func make(dailyFraction: Double?, weeklyFraction: Double, monthlyFraction: Double) -> NSImage {
        let hasDailyLimit = dailyFraction != nil
        let image = NSImage(size: NSSize(width: hasDailyLimit ? 56 : 36, height: 16))
        image.lockFocus()
        if let dailyFraction {
            drawRing(center: NSPoint(x: 8, y: 8), fraction: dailyFraction)
            drawRing(center: NSPoint(x: 28, y: 8), fraction: weeklyFraction)
            drawRing(center: NSPoint(x: 48, y: 8), fraction: monthlyFraction)
        } else {
            drawRing(center: NSPoint(x: 8, y: 8), fraction: weeklyFraction)
            drawRing(center: NSPoint(x: 28, y: 8), fraction: monthlyFraction)
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func drawRing(center: NSPoint, fraction: Double) {
        let radius: CGFloat = 5.5
        let background = NSBezierPath(ovalIn: NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        background.lineWidth = 2.5
        NSColor.white.withAlphaComponent(0.22).setStroke()
        background.stroke()

        let clamped = min(max(fraction, 0), 1)
        guard clamped > 0 else { return }
        let progress = NSBezierPath()
        progress.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - CGFloat(clamped) * 360,
            clockwise: true
        )
        progress.lineWidth = 2.5
        progress.lineCapStyle = .round
        NSColor.white.setStroke()
        progress.stroke()
    }
}
