import SwiftUI

/// Floating charging status shown in the top-left corner of every tab while a
/// session is running (except on the Charging tab itself). Tap opens the
/// Charging tab; × hides it until the session moves to its next phase.
struct ChargingTile: View {
    enum Style { case square, compact }

    var style: Style = .square

    @Environment(AppModel.self) private var model

    var body: some View {
        if let session = model.session, model.tab != .charging {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let snap = SessionSnapshot(session, now: model.simNow())
                if model.tileHiddenFor != snap.phase {
                    tile(TileContent(session, snap))
                        .transition(.scale(scale: 0.8, anchor: .topLeading).combined(with: .opacity))
                }
            }
        }
    }

    @ViewBuilder
    private func tile(_ c: TileContent) -> some View {
        switch style {
        case .square: square(c)
        case .compact: compact(c)
        }
    }

    private func square(_ c: TileContent) -> some View {
        Button { model.tab = .charging } label: {
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
        .accessibilityLabel(Text("Charging status: \(c.title), \(c.subtitle)"))
        .accessibilityHint(Text("Opens charging details"))
        .overlay(alignment: .topTrailing) { closeButton.offset(x: -6, y: 6) }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func compact(_ c: TileContent) -> some View {
        Button { model.tab = .charging } label: {
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
            .padding(.trailing, 30)
            .padding(.vertical, 7)
            .glass(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Charging status: \(c.title), \(c.subtitle)"))
        .accessibilityHint(Text("Opens charging details"))
        .overlay(alignment: .trailing) { closeButton.padding(.trailing, 6) }
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
            subtitle = Fmt.eur(snap.chargingCost + snap.idleFee)
            symbol = "checkmark"
            color = Theme.ok
            progress = 1
        }
    }
}
