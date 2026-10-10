import SwiftUI

/// Floating charging status shown in the top-left corner of every tab while a
/// session exists (except on the Charging tab itself). It is a permanent
/// indicator: it cannot be hidden, and tapping anywhere on it opens the
/// Charging tab. With no session but a spot held for you, it counts down the
/// hold instead and opens that station.
struct ChargingTile: View {
    enum Style { case square, compact }

    /// Which tile, if any, to show.
    enum Kind: Equatable { case session, hold }

    /// The tile's decision, kept pure so it can be tested: the session tile
    /// shows whenever a session exists and the tab is not Charging; otherwise a
    /// held spot shows its countdown. There is no hidden state.
    static func kind(hasSession: Bool, hasHold: Bool, tab: AppTab) -> Kind? {
        if hasSession && tab != .charging { return .session }
        if !hasSession && hasHold { return .hold }
        return nil
    }

    var style: Style = .square

    @Environment(AppModel.self) private var model

    var body: some View {
        switch Self.kind(hasSession: model.session != nil, hasHold: model.myHold != nil, tab: model.tab) {
        case .session:
            if let session = model.session {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    let snap = SessionSnapshot(session, now: model.simNow())
                    let c = TileContent(session, snap)
                    tile(c, label: tr("Charging status: \(c.title), \(c.subtitle)"),
                         hint: tr("Opens charging details")) { model.tab = .charging }
                        .transition(.scale(scale: 0.8, anchor: .topLeading).combined(with: .opacity))
                }
            }
        case .hold:
            if let hold = model.myHold {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    let c = TileContent(hold: hold, now: model.simNow())
                    tile(c, label: tr("Spot held for you: \(c.title)"),
                         hint: tr("Opens the station")) { model.openStation(hold.stationId) }
                        .transition(.scale(scale: 0.8, anchor: .topLeading).combined(with: .opacity))
                }
            }
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func tile(_ c: TileContent, label: String, hint: String, action: @escaping () -> Void) -> some View {
        Group {
            switch style {
            case .square: square(c, action: action)
            case .compact: compact(c, action: action)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityHint(Text(hint))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func square(_ c: TileContent, action: @escaping () -> Void) -> some View {
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
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func compact(_ c: TileContent, action: @escaping () -> Void) -> some View {
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
            .padding(.trailing, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .glass(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
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
            subtitle = Fmt.eurPerMin(IdleFee.currentRate(minutes: snap.idleMinutes))
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
