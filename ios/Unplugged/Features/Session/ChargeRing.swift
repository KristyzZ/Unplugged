import SwiftUI

/// The charging ring. Like a car's charge-limit gauge it shows the battery
/// level, the part still planned up to the limit (dim), and a tick at the
/// limit. While charging, a soft light runs along the filled arc so the
/// energy visibly flows in (off with Reduce Motion).
struct ChargeRing<Center: View>: View {
    /// Battery level, 0…1.
    var progress: Double
    /// Charge limit, 0…1. Hidden when nil.
    var limit: Double? = nil
    var color: Color
    var lineWidth: CGFloat = 14
    var flowing = false
    @ViewBuilder var center: Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func clamp(_ v: Double) -> Double { min(1, max(0, v)) }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let p = clamp(progress)
            ZStack {
                Circle()
                    .inset(by: lineWidth / 2)
                    .stroke(Theme.fill, lineWidth: lineWidth)

                if let limit {
                    arc(to: clamp(limit))
                        .stroke(color.opacity(0.2), style: stroke)
                }

                arc(to: max(0.001, p))
                    .stroke(color, style: stroke)
                    .shadow(color: color.opacity(flowing ? 0.45 : 0), radius: 10)
                    .animation(Motion.pick(.easeOut(duration: 0.6)), value: p)

                if flowing && !reduceMotion && p > 0.05 {
                    TimelineView(.animation) { context in
                        let cycle = 1.8
                        let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
                        let head = p * t
                        Circle()
                            .inset(by: lineWidth / 2)
                            .trim(from: max(0, head - 0.08), to: head)
                            .rotation(.degrees(-90))
                            .stroke(Color.white.opacity(0.55), style: stroke)
                            .blur(radius: 3)
                            .opacity(sin(.pi * t))
                    }
                    .allowsHitTesting(false)
                }

                if let limit, limit < 0.995 {
                    Capsule()
                        .fill(Theme.text)
                        .frame(width: 3, height: lineWidth + 8)
                        .offset(y: -(size - lineWidth) / 2)
                        .rotationEffect(.degrees(360 * clamp(limit)))
                        .accessibilityHidden(true)
                }

                center
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var stroke: StrokeStyle { StrokeStyle(lineWidth: lineWidth, lineCap: .round) }

    private func arc(to end: Double) -> some Shape {
        // Inset so the stroke stays inside the frame and the limit tick lines up.
        Circle().inset(by: lineWidth / 2).trim(from: 0, to: end).rotation(.degrees(-90))
    }
}

/// Check mark drawn as a line, so it can animate with `trim`.
struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.27, y: r.minY + r.height * 0.53))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.43, y: r.minY + r.height * 0.69))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.74, y: r.minY + r.height * 0.36))
        return p
    }
}

/// A short burst of sparks around a circle, for "done" moments.
struct SparkBurst: View {
    var color: Color
    var radius: CGFloat
    var count = 14

    @State private var fired = false

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i.isMultiple(of: 2) ? color : Theme.text.opacity(0.85))
                    .frame(width: 3, height: i.isMultiple(of: 2) ? 12 : 7)
                    .offset(y: -(fired ? radius + (i.isMultiple(of: 2) ? 44 : 30) : radius + 4))
                    .rotationEffect(.degrees(Double(i) / Double(count) * 360 + 6))
                    .opacity(fired ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { fired = true }
        }
    }
}
