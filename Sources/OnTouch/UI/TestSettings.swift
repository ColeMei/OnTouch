import SwiftUI

/// Settings → Test: a live trackpad showing the fingers OnTouch sees (held
/// finger solid, acting fingers as rings, ignored edge touches dashed), and the
/// last few gestures — with a one-click fix for near misses.
struct TestSettings: View {
    @ObservedObject var status: AppStatus
    @ObservedObject private var monitor = TestMonitor.shared
    @StateObject private var renderer = PadRenderer()

    var body: some View {
        VStack(spacing: 14) {
            TimelineView(.animation) { context in
                TrackpadView(pad: TestMonitor.pad, config: status.config, date: context.date, renderer: renderer)
            }
            .frame(width: 460, height: 290)

            VStack(spacing: 0) {
                if monitor.events.isEmpty {
                    Text("Try a gesture").font(.system(size: 13)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).frame(height: 36)
                }
                ForEach(Array(monitor.events.enumerated()), id: \.element.id) { i, e in
                    if i > 0 { Divider() }
                    eventRow(e)
                }
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
            .frame(width: 560)

            Spacer(minLength: 0)
        }
        .padding(.top, 20)
        .frame(width: SettingsWindowController.contentSize.width,
               height: SettingsWindowController.contentSize.height)
        .onAppear { TestMonitor.active = true }
        .onDisappear { TestMonitor.active = false }
    }

    private func eventRow(_ e: TestMonitor.Event) -> some View {
        HStack(spacing: 10) {
            GestureGlyph(fingers: e.fingers, type: e.type, direction: e.direction)
                .frame(width: 32, height: 22)
                .opacity(e.outcome == .fired ? 1 : 0.5)
            switch e.outcome {
            case .fired:
                Text(e.text).font(.system(size: 13))
                Spacer()
                if let app = e.app { Text(AppNames.name(app)).font(.system(size: 12)).foregroundStyle(.secondary) }
                Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
            case .missed:
                Text(e.text).font(.system(size: 13)).foregroundStyle(.orange)
                Spacer()
                if let fix = e.fix {
                    Button("Loosen") { ConfigStore.shared.update([fix.key: fix.value]) }.controlSize(.small)
                }
            case .notTarget:
                Text(e.app.map(AppNames.name) ?? "Unknown app").font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                if let app = e.app, !status.config.targetBundleIDs.contains(app) {
                    Button("Add app") { status.acceptSuggestion(app) }.controlSize(.small)
                }
            }
        }
        .frame(height: 36)
    }
}

/// The trackpad drawing, at the real trackpad's proportions. Fingers are
/// their reported contact ellipses; they ease in and out and blend between
/// roles rather than snapping, so the drawing stays calm.
private struct TrackpadView: View {
    let pad: TestMonitor.Pad
    let config: Config
    let date: Date
    let renderer: PadRenderer

    var body: some View {
        Canvas { ctx, box in
            renderer.step(pad, at: date)
            let aspect = pad.size.width / pad.size.height
            let size = box.width / box.height > aspect
                ? CGSize(width: box.height * aspect, height: box.height)
                : CGSize(width: box.width, height: box.width / aspect)
            ctx.translateBy(x: (box.width - size.width) / 2, y: (box.height - size.height) / 2)
            let w = size.width, h = size.height
            let mm = w / pad.size.width     // points per millimetre

            let surface = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 9 * mm)
            ctx.fill(surface, with: .color(Color(nsColor: .controlBackgroundColor)))
            ctx.drawLayer { layer in
                // Edge strips where a touch counts as a resting thumb or palm.
                layer.clip(to: surface)
                let strips = [
                    CGRect(x: 0, y: h * (1 - config.anchorEdgeZone), width: w, height: h * config.anchorEdgeZone),
                    CGRect(x: 0, y: 0, width: w, height: h * config.topEdgeZone),
                    CGRect(x: 0, y: 0, width: w * config.sideEdgeZone, height: h),
                    CGRect(x: w * (1 - config.sideEdgeZone), y: 0, width: w * config.sideEdgeZone, height: h),
                ]
                for r in strips { layer.fill(Path(r), with: .color(.primary.opacity(0.035))) }
            }
            ctx.stroke(surface, with: .color(.primary.opacity(0.14)), lineWidth: 1)

            for dot in renderer.dots.values where dot.alpha > 0.01 {
                let c = CGPoint(x: dot.pos.x * w, y: (1 - dot.pos.y) * h)
                let rx = min(max(dot.major * mm, 18), 64) / 2
                let ry = min(max(dot.minor * mm, 16), 56) / 2
                var t = ctx
                t.translateBy(x: c.x, y: c.y)
                t.rotate(by: .radians(-Double(dot.angle)))
                t.opacity = Double(dot.alpha)
                let blob = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
                if dot.resting {
                    t.fill(blob, with: .color(.secondary.opacity(0.18)))
                } else {
                    // Acting: a pale disc with a ring. Held: the disc fills in.
                    t.fill(blob, with: .color(.accentColor.opacity(0.16 + 0.64 * dot.anchor)))
                    t.stroke(blob, with: .color(.accentColor.opacity(0.9 - 0.5 * dot.anchor)), lineWidth: 1.5)
                }
            }
        }
        .accessibilityLabel("Live trackpad")
    }
}

/// Eased display state per finger, stepped once per drawn frame.
private final class PadRenderer: ObservableObject {
    struct Dot {
        var pos: CGPoint
        var major: CGFloat, minor: CGFloat, angle: CGFloat
        var alpha: CGFloat = 0
        var anchor: CGFloat = 0
        var resting = false
    }
    private(set) var dots: [Int32: Dot] = [:]
    private var last: Date?

    func step(_ pad: TestMonitor.Pad, at date: Date) {
        let dt = CGFloat(min(max(date.timeIntervalSince(last ?? date), 0), 0.1))
        last = date
        // Time constants (s): position barely smoothed, so it stays accurate;
        // fades and role changes a touch slower, so they read as motion.
        func ease(_ tau: CGFloat) -> CGFloat { dt == 0 ? 1 : 1 - exp(-dt / tau) }
        let kPos = ease(0.02), kFade = ease(0.07), kRole = ease(0.08)

        let live = Dictionary(pad.touches.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, t) in live {
            var d = dots[id] ?? Dot(pos: t.pos, major: t.shape.major, minor: t.shape.minor, angle: t.shape.angle)
            d.pos.x += (t.pos.x - d.pos.x) * kPos
            d.pos.y += (t.pos.y - d.pos.y) * kPos
            d.major += (t.shape.major - d.major) * kPos
            d.minor += (t.shape.minor - d.minor) * kPos
            d.angle = t.shape.angle
            d.alpha += (1 - d.alpha) * kFade
            d.anchor += ((t.role == .anchor ? 1 : 0) - d.anchor) * kRole
            d.resting = t.role == .resting
            dots[id] = d
        }
        for id in dots.keys where live[id] == nil {
            dots[id]!.alpha -= dots[id]!.alpha * kFade
            if dots[id]!.alpha < 0.01 { dots[id] = nil }
        }
    }
}
