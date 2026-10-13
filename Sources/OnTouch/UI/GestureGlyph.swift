import SwiftUI

/// A small trackpad drawing of a gesture: the held finger solid, the acting
/// fingers as rings, and an arrow per finger for swipes. Drawn on a 48×34 grid
/// and scaled to fit.
struct GestureGlyph: View {
    let fingers: Int
    let type: String        // "tap" | "swipe"
    let direction: String   // left/right/up/down/any

    init(_ m: Mapping) {
        self.init(fingers: m.fingers, type: m.type, direction: m.direction)
    }

    init(fingers: Int, type: String, direction: String) {
        self.fingers = max(1, min(fingers, 3))
        self.type = type
        self.direction = direction
    }

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / 48, size.height / 34)
            ctx.translateBy(x: (size.width - 48 * s) / 2, y: (size.height - 34 * s) / 2)
            ctx.scaleBy(x: s, y: s)

            let pad = Path(roundedRect: CGRect(x: 1, y: 1, width: 46, height: 32), cornerRadius: 6)
            ctx.stroke(pad, with: .color(.secondary.opacity(0.6)), lineWidth: 1.8)

            let (anchor, acting, arrow) = layout()
            ctx.fill(Path(ellipseIn: circle(anchor, 4.5)), with: .color(.primary))
            for p in acting {
                ctx.stroke(Path(ellipseIn: circle(p, type == "swipe" ? 3.2 : 4)), with: .color(.accentColor), lineWidth: 2.2)
                if let v = arrow { ctx.stroke(arrowPath(from: p, along: v), with: .color(.accentColor),
                                              style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)) }
            }
        }
        .accessibilityLabel(Text(Self.describe(fingers: fingers, type: type, direction: direction)))
    }

    /// Anchor position, acting finger positions, and swipe vector (nil for taps).
    private func layout() -> (CGPoint, [CGPoint], CGVector?) {
        let n = fingers
        if type == "swipe" {
            switch direction {
            case "up":    return (CGPoint(x: 12, y: 12), (0..<n).map { CGPoint(x: 26 + Double($0) * 8, y: 26) }, CGVector(dx: 0, dy: -1))
            case "left":  return (CGPoint(x: 40, y: 26), (0..<n).map { CGPoint(x: 34, y: 8 + Double($0) * 7) }, CGVector(dx: -1, dy: 0))
            case "right": return (CGPoint(x: 8, y: 26), (0..<n).map { CGPoint(x: 14, y: 8 + Double($0) * 7) }, CGVector(dx: 1, dy: 0))
            default:      return (CGPoint(x: 12, y: 20), (0..<n).map { CGPoint(x: 26 + Double($0) * 8, y: 9) }, CGVector(dx: 0, dy: 1))
            }
        }
        switch direction {
        case "left": return (CGPoint(x: 34, y: 18), (0..<n).map { CGPoint(x: 20 - Double($0) * 8, y: 18) }, nil)
        case "up":   return (CGPoint(x: 24, y: 25), (0..<n).map { CGPoint(x: 24 + (Double($0) - Double(n - 1) / 2) * 9, y: 10) }, nil)
        case "down": return (CGPoint(x: 24, y: 10), (0..<n).map { CGPoint(x: 24 + (Double($0) - Double(n - 1) / 2) * 9, y: 25) }, nil)
        default:     return (CGPoint(x: 14, y: 18), (0..<n).map { CGPoint(x: 28 + Double($0) * 8, y: 18) }, nil)
        }
    }

    private func circle(_ c: CGPoint, _ r: Double) -> CGRect {
        CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }

    private func arrowPath(from p: CGPoint, along v: CGVector) -> Path {
        let start = CGPoint(x: p.x + v.dx * 4.5, y: p.y + v.dy * 4.5)
        let end = CGPoint(x: p.x + v.dx * 16, y: p.y + v.dy * 16)
        let back = CGPoint(x: end.x - v.dx * 3.5, y: end.y - v.dy * 3.5)
        let side = CGVector(dx: -v.dy * 3, dy: v.dx * 3)
        var path = Path()
        path.move(to: start); path.addLine(to: end)
        path.move(to: CGPoint(x: back.x + side.dx, y: back.y + side.dy))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: back.x - side.dx, y: back.y - side.dy))
        return path
    }

    /// "Tap left", "Two-finger swipe down", … — also used as row labels.
    static func describe(fingers: Int, type: String, direction: String) -> String {
        let count = ["", "", "Two-finger ", "Three-finger "][max(0, min(fingers, 3))]
        let verb = type == "swipe" ? "swipe" : "tap"
        let dir = direction == "any" ? "" : " \(direction)"
        let text = count + verb + dir
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
