import AppKit
import CoreText

enum StatusIcon {
    static func image(remaining: Int) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let badge = rect.insetBy(dx: 1.25, dy: 1.25)
            let outline = NSBezierPath(roundedRect: badge, xRadius: 3.5, yRadius: 3.5)
            outline.lineWidth = 1.35
            NSColor.black.setStroke()
            outline.stroke()

            if remaining <= 0 {
                drawCheck(in: badge)
            } else if remaining > 9 {
                drawCenteredText(
                    "…",
                    font: NSFont.systemFont(ofSize: 10, weight: .bold),
                    in: badge
                )
            } else {
                drawCenteredText(
                    "\(remaining)",
                    font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    in: badge
                )
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawCenteredText(_ text: String, font: NSFont, in rect: NSRect) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.black,
        ]))
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let bounds = CTLineGetImageBounds(line, context)
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(
            x: rect.midX - bounds.midX,
            y: rect.midY - bounds.midY
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func drawCheck(in rect: NSRect) {
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: rect.minX + rect.width * 0.22, y: rect.midY))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.28))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.76, y: rect.minY + rect.height * 0.70))
        NSColor.black.setStroke()
        path.stroke()
    }
}
