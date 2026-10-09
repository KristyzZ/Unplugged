import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct UnpluggedWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ChargingLiveActivity()
    }
}

// The charging session on the Lock Screen and in the Dynamic Island.
//
// Nothing here needs the app to be running: the charge bar and countdowns are
// system timers on wall-clock dates, and when charging ends the activity's
// stale date makes the system redraw it as "move your car" (see
// ChargingActivityAttributes.shownPhase). The one button runs an App Intent.

/// Same palette as the app (see UI/Theme.swift).
private enum WTheme {
    static let background = Color(red: 0x15 / 255, green: 0x15 / 255, blue: 0x1B / 255)
    static let violet = Color(red: 0xA7 / 255, green: 0x8B / 255, blue: 0xFA / 255)
    static let amber = Color(red: 0xE8 / 255, green: 0xB0 / 255, blue: 0x4E / 255)
    static let red = Color(red: 0xE5 / 255, green: 0x63 / 255, blue: 0x6A / 255)
    static let green = Color(red: 0x5B / 255, green: 0xC4 / 255, blue: 0x8A / 255)
    static let text = Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255)
    static let muted = Color(red: 0xA1 / 255, green: 0xA1 / 255, blue: 0xAA / 255)
    static let track = Color.white.opacity(0.12)
    static let ink = Color(red: 0x15 / 255, green: 0x15 / 255, blue: 0x1B / 255)
}

private typealias Phase = ChargingActivityAttributes.ContentState.Phase
private typealias Context = ActivityViewContext<ChargingActivityAttributes>

/// Everything a view needs: the state plus the phase to show right now.
private struct Live {
    let attributes: ChargingActivityAttributes
    let state: ChargingActivityAttributes.ContentState
    let phase: Phase

    init(_ context: Context) {
        attributes = context.attributes
        state = context.state
        phase = context.state.shownPhase(isStale: context.isStale)
    }

    var color: Color {
        switch phase {
        case .charging: WTheme.violet
        case .grace: WTheme.amber
        case .idle: WTheme.red
        case .ended: WTheme.green
        }
    }

    var symbol: String {
        switch phase {
        case .charging: "bolt.fill"
        case .grace: "car.side.fill"
        case .idle: "exclamationmark"
        case .ended: "checkmark"
        }
    }

    var lt: Bool { attributes.lang == "lt" }
    func t(_ en: String, _ ltText: String) -> String { lt ? ltText : en }

    /// Was this phase reached by the clock rather than by an update from the app?
    var reachedByClock: Bool { phase != state.phase }

    /// Battery level reached when charging ended.
    var finalSoc: Int { Int((state.phase == .charging ? state.targetSoc : state.soc).rounded()) }

    var title: String {
        switch phase {
        case .charging: t("Charging to \(Int(state.targetSoc)) %", "Kraunama iki \(Int(state.targetSoc)) %")
        case .grace: t("Charged to \(finalSoc) %", "Įkrauta iki \(finalSoc) %")
        case .idle: t("Idle fee is running", "Skaičiuojamas prastovos mokestis")
        case .ended: t("Spot freed. Thanks!", "Vieta atlaisvinta. Ačiū!")
        }
    }

    var subtitle: String { "\(attributes.stationName) · \(attributes.connectorLabel)" }

    /// Small caption under the big value on the right.
    var valueCaption: String {
        switch phase {
        case .charging: t("left", "liko")
        case .grace: t("free time", "nemokamai")
        case .idle: t("idle", "prastova")
        case .ended: t("total", "iš viso")
        }
    }
}

private func euros(_ v: Double) -> String { String(format: "%.2f €", v) }

// MARK: - Widget

struct ChargingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChargingActivityAttributes.self) { context in
            LockScreenView(live: Live(context))
                .activityBackgroundTint(WTheme.background.opacity(0.92))
                .activitySystemActionForegroundColor(WTheme.text)
        } dynamicIsland: { context in
            let live = Live(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        PhaseBadge(live: live, size: 34)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(live.attributes.stationName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WTheme.text)
                                .lineLimit(1)
                            Text(live.attributes.connectorLabel)
                                .font(.caption2)
                                .foregroundStyle(WTheme.muted)
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    BigValue(live: live, size: 24)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    PhaseBody(live: live, compact: true)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                }
            } compactLeading: {
                CompactRing(live: live)
            } compactTrailing: {
                CompactValue(live: live)
            } minimal: {
                CompactRing(live: live)
            }
            .keylineTint(live.color)
        }
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let live: Live

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                PhaseBadge(live: live, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(live.title)
                        .font(.headline)
                        .foregroundStyle(WTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(live.subtitle)
                        .font(.caption)
                        .foregroundStyle(WTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                BigValue(live: live, size: 26)
            }
            PhaseBody(live: live, compact: false)
        }
        .padding(14)
    }
}

/// Coloured circle with the phase symbol.
private struct PhaseBadge: View {
    let live: Live
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(live.color.opacity(0.18))
            Image(systemName: live.symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(live.color)
        }
        .frame(width: size, height: size)
    }
}

/// The big number on the right: a live countdown, the idle time or the total.
private struct BigValue: View {
    let live: Live
    let size: CGFloat

    var body: some View {
        let s = live.state
        VStack(alignment: .trailing, spacing: 0) {
            Group {
                switch live.phase {
                case .charging:
                    Text(timerInterval: s.chargeStart...s.chargeEnd, countsDown: true)
                case .grace:
                    Text(timerInterval: s.chargeEnd...s.graceEnd, countsDown: true)
                case .idle:
                    // Counts up from when the free time ran out.
                    Text(timerInterval: s.graceEnd...s.graceEnd.addingTimeInterval(8 * 3600), countsDown: false)
                case .ended:
                    Text(euros(s.totalEur))
                }
            }
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(live.phase == .charging || live.phase == .ended ? WTheme.text : live.color)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 120, alignment: .trailing)

            Text(live.valueCaption)
                .font(.caption2.weight(.medium))
                .foregroundStyle(WTheme.muted)
        }
    }
}

/// Bar, one line of detail and, when it matters, the "I moved my car" button.
private struct PhaseBody: View {
    let live: Live
    let compact: Bool

    var body: some View {
        let s = live.state
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            switch live.phase {
            case .charging:
                ChargeBar(state: s)
                HStack {
                    Text("\(Int(s.startSoc)) % → \(Int(s.targetSoc)) %")
                    Spacer(minLength: 8)
                    Text(live.t("Full at ", "Bus pilna ")) + Text(s.chargeEnd, style: .time)
                }
                .detailStyle()
                HStack {
                    Text("\(Int(s.powerKw)) kW · ≈ \(euros(s.totalEur))")
                    Spacer(minLength: 8)
                    // Plain clock times stay true even if nothing redraws this view.
                    Text(live.t("then free until ", "toliau nemokamai iki ")) + Text(s.graceEnd, style: .time)
                }
                .detailStyle()

            case .grace:
                ProgressView(timerInterval: s.chargeEnd...s.graceEnd, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(WTheme.amber)
                (Text(live.t("Move by ", "Patraukite iki ")) + Text(s.graceEnd, style: .time)
                    + Text(live.t(" to avoid the idle fee · up to +\(s.points) pts",
                                  " ir išvengsite prastovos mokesčio · iki +\(s.points) tšk.")))
                    .detailStyle(lines: 2)
                MovedButton(live: live)

            case .idle:
                (Text(live.t("Since ", "Nuo ")) + Text(s.graceEnd, style: .time)
                    + Text(live.t(" · the rate keeps rising. Others are waiting.",
                                  " · tarifas didėja. Kiti laukia.")))
                    .detailStyle(lines: 2)
                MovedButton(live: live)

            case .ended:
                HStack {
                    if s.handedOver == true {
                        Text(live.t("Next driver notified", "Kitas vairuotojas informuotas"))
                    } else {
                        Text(live.t("Charged to \(Int(s.soc)) %", "Įkrauta iki \(Int(s.soc)) %"))
                    }
                    if s.idleFeeEur > 0 {
                        Text(live.t("· idle fee \(euros(s.idleFeeEur))", "· prastova \(euros(s.idleFeeEur))"))
                            .foregroundStyle(WTheme.red)
                    }
                    Spacer(minLength: 8)
                    if s.points > 0 {
                        Text(live.t("+\(s.points) pts", "+\(s.points) tšk."))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WTheme.green)
                    }
                }
                .detailStyle()
            }
        }
    }
}

private extension View {
    func detailStyle(lines: Int = 1) -> some View {
        font(.caption).foregroundStyle(WTheme.muted).lineLimit(lines)
    }
}

/// Battery from 0 to 100 %: what was already in it, the part being added
/// (a system timer fills it, so it moves with the app closed), the charge
/// limit as a tick, and the rest dimmed — like a car's charge-limit gauge.
private struct ChargeBar: View {
    let state: ChargingActivityAttributes.ContentState

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let start = w * min(1, max(0, state.startSoc / 100))
            let target = max(start + 2, w * min(1, max(0, state.targetSoc / 100)))
            // Square segments inside one rounded clip, so they meet without seams.
            ZStack(alignment: .leading) {
                Rectangle().fill(WTheme.track)
                Rectangle().fill(WTheme.violet.opacity(0.22)).frame(width: target)
                ProgressView(timerInterval: state.chargeStart...state.chargeEnd, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(WTheme.violet)
                .frame(width: target - start + 6)
                .scaleEffect(x: 1, y: 2.6, anchor: .center)
                .offset(x: start - 6)
                Rectangle().fill(WTheme.violet).frame(width: start)
            }
            .frame(height: 8)
            .clipShape(Capsule())
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(WTheme.text)
                    .frame(width: 3, height: 16)
                    .offset(x: target - 1.5)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 16)
    }
}

/// The one action that matters once charging is done.
private struct MovedButton: View {
    let live: Live

    var body: some View {
        Button(intent: MovedCarIntent()) {
            HStack(spacing: 6) {
                Image(systemName: "car.side.fill")
                Text(live.t("I moved my car", "Patraukiau automobilį"))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(WTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(live.color, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dynamic Island, compact

/// A small ring that fills on its own while charging, then counts down the free time.
private struct CompactRing: View {
    let live: Live

    var body: some View {
        let s = live.state
        Group {
            switch live.phase {
            case .charging:
                ProgressView(timerInterval: s.chargeStart...s.chargeEnd, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold))
                }
                .progressViewStyle(.circular)
            case .grace:
                ProgressView(timerInterval: s.chargeEnd...s.graceEnd, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: "car.side.fill").font(.system(size: 8, weight: .bold))
                }
                .progressViewStyle(.circular)
            case .idle, .ended:
                Image(systemName: live.symbol)
                    .font(.system(size: 13, weight: .bold))
            }
        }
        .tint(live.color)
        .foregroundStyle(live.color)
        .frame(width: 24, height: 24)
    }
}

private struct CompactValue: View {
    let live: Live

    var body: some View {
        let s = live.state
        Group {
            switch live.phase {
            case .charging:
                Text(timerInterval: s.chargeStart...s.chargeEnd, countsDown: true)
            case .grace:
                Text(timerInterval: s.chargeEnd...s.graceEnd, countsDown: true)
            case .idle:
                Text(String(format: "%.2f€", s.idleRateEurPerMin))
            case .ended:
                Text(live.t("Done", "Baigta"))
            }
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(live.color)
        .multilineTextAlignment(.trailing)
        .frame(width: 50, alignment: .trailing)
    }
}

// MARK: - Previews (Xcode canvas)

#if DEBUG
private extension ChargingActivityAttributes {
    static var preview: ChargingActivityAttributes {
        .init(sessionStart: .now, stationName: "Lukiškės Square", connectorLabel: "CCS2 · 150 kW", lang: "en")
    }
}

private extension ChargingActivityAttributes.ContentState {
    static func preview(_ phase: Phase) -> Self {
        let now = Date()
        let charging = phase == .charging
        return .init(
            phase: phase,
            soc: charging ? 52 : 80,
            startSoc: 34,
            targetSoc: 80,
            chargeStart: now.addingTimeInterval(-600),
            chargeEnd: charging ? now.addingTimeInterval(900) : now.addingTimeInterval(-60),
            graceEnd: phase == .idle ? now.addingTimeInterval(-240) : now.addingTimeInterval(540),
            powerKw: 96,
            energyCostEur: charging ? 9.4 : 22.1,
            totalEur: phase == .idle ? 22.9 : 22.1,
            idleRateEurPerMin: 0.2,
            idleFeeEur: phase == .idle ? 0.8 : 0,
            points: 30
        )
    }
}

#Preview("Lock Screen", as: .content, using: ChargingActivityAttributes.preview) {
    ChargingLiveActivity()
} contentStates: {
    ChargingActivityAttributes.ContentState.preview(.charging)
    ChargingActivityAttributes.ContentState.preview(.grace)
    ChargingActivityAttributes.ContentState.preview(.idle)
    ChargingActivityAttributes.ContentState.preview(.ended)
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: ChargingActivityAttributes.preview) {
    ChargingLiveActivity()
} contentStates: {
    ChargingActivityAttributes.ContentState.preview(.charging)
    ChargingActivityAttributes.ContentState.preview(.grace)
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: ChargingActivityAttributes.preview) {
    ChargingLiveActivity()
} contentStates: {
    ChargingActivityAttributes.ContentState.preview(.charging)
    ChargingActivityAttributes.ContentState.preview(.grace)
}
#endif
