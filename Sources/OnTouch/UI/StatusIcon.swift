import AppKit

/// The menu-bar icon: a trackpad with a held finger and a tapping finger.
enum StatusIcon {
    /// `attention` adds an orange dot (a permission or the trackpad is missing).
    /// The plain icon is a template so macOS tints it for light/dark menu bars;
    /// the attention icon draws in the label color itself to keep the dot orange.
    static func image(attention: Bool, dimmed: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 16)
        let image = NSImage(size: size, flipped: true) { _ in
            let ink = attention ? NSColor.labelColor : NSColor.black
            ink.withAlphaComponent(dimmed ? 0.45 : 1).set()

            let pad = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2.5, width: 18, height: 12), xRadius: 3, yRadius: 3)
            pad.lineWidth = 1.4
            pad.stroke()
            NSBezierPath(ovalIn: NSRect(x: 5, y: 6.5, width: 4, height: 4)).fill()
            let ring = NSBezierPath(ovalIn: NSRect(x: 12.4, y: 6.9, width: 3.2, height: 3.2))
            ring.lineWidth = 1.2
            ring.stroke()

            if attention {
                NSColor.systemOrange.set()
                NSBezierPath(ovalIn: NSRect(x: 16, y: 0, width: 6, height: 6)).fill()
            }
            return true
        }
        image.isTemplate = !attention
        image.accessibilityDescription = attention ? "OnTouch needs attention" : "OnTouch"
        return image
    }
}
