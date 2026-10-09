import SwiftUI

/// Floating charging status shown in the top-left corner of every tab while a
/// session is running (except on the Charging tab itself). Tap opens the
/// Charging tab; × hides it until the session moves to its next phase.
/// With no session but a spot held for you, it counts down the hold instead
/// and opens that station.
struct ChargingTile: View {
    enum Style { case square, compact }

    var style: Style = .square

    @Environment(AppModel.self) private var model

    var body: some View {
        if let session = model.session, model.tab != .charging {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let snap = SessionSnapshot(session, now: model.simNow())
                if model.tileHiddenFor != snap.phase {
                    tile(TileContent(session, snap), closable: true) { model.tab = .charging }
                        .transition(.scale(scale: 0.8, anchor: .topLeading).combined(with: .opacity))
                }
            }
        } else if let hold = model.myHold {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                tile(TileContent(hold: hold, now: model.simNow()), closable: false) { model.openStation(hold.stationId) }
                    .transition(.scale(scale: 0.8, anchor: .topLeading).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func tile(_ c: TileContent, closable: Bool, action: @escaping () -> Void) -> some View {
        switch style {
        case .square: square(c, closable: closable, action: action)
        case .compact: compact(c, closable: closable, action: action)
        }
    }

    private func square(_ c: TileContent, closable: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ProgressRing(progress: c.progress, color: c.color, lineWidth: 4) {
                    Image(systemName: c.symbol)
                        .scaledFont(17, weight: .bold, relativeTo: .body)
                        .foregroundStyle(c.color)
                }
                .frame(width: 44, height: 44)
                VStack(spacing: 0) {
                    Text(c.title)
                        .scaledFont(20, weight: .bold, design: .rounded, relativeTo: .title3)
                        .foregroundStyle(Theme.text)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(c.subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 92, height: 104)
            .glass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(c.title), \(c.subtitle)"))
        .overlay(alignment: .topTrailing) { if closable { closeButton.offset(x: -6, y: 6) } }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func compact(_ c: TileContent, closable: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ProgressRing(progress: c.progress, color: c.color, lineWidth: 3) {
                    Image(systemName: c.symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(c.color)
                }
                .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(c.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .monospacedDigit()
                    Text(c.subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, closable ? 30 : 12)
            .padding(.vertical, 7)
            .glass(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(c.title), \(c.subtitle)"))
        .overlay(alignment: .trailing) { if closable { closeButton.padding(.trailing, 6) } }
        .fixedSize()
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var closeButton: some View {
        Button {
            withMotion(.spring(duration: 0.3)) { model.hideTile() }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.muted)
                .frame(width: 20, height: 20)
                .background(Color.white.opacity(0.12), in: Circle())
                .contentShape(Circle().inset(by: -12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Hide charging status"))
    }
}

/// What the tile shows in each phase of the session.
private struct TileContent {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let progress: Double

    /// A spot held for you: time left to get there.
    init(hold: SpotHold, now: Date) {
        let left = max(0, hold.until.timeIntervalSince(now))
        title = Fmt.mmss(left)
        subtitle = tr("Held for you")
        symbol = "parkingsign"
        color = Theme.brand
        progress = left / max(1, hold.duration)
    }

    init(_ s: ChargingSession, _ snap: SessionSnapshot) {
        switch snap.phase {
        case .charging:
            title = "\(Int(snap.soc.rounded())) %"
            subtitle = Fmt.minutes(snap.minutesLeft)
            symbol = "bolt.fill"
            color = Theme.brand
            progress = snap.soc / 100
        case .grace:
            title = Fmt.mmss(snap.graceLeft)
            subtitle = tr("Move your car")
            symbol = "car.fill"
            color = Theme.warn
            progress = snap.graceLeft / max(1, Double(s.graceMinutes) * 60)
        case .idle:
            title = "+" + Fmt.eur(snap.idleFee)
            subtitle = String(format: "%.2f €/min", IdleFee.currentRate(minutes: snap.idleMinutes))
            symbol = "exclamationmark"
            color = Theme.bad
            progress = 1
        case .ended:
            title = tr("Done")
            subtitle = Fmt.eur(snap.energyCost + snap.idleFee)
            symbol = "checkmark"
            color = Theme.ok
            progress = 1
        }
    }
}
