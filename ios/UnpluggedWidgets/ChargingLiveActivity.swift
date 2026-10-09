import ActivityKit
import SwiftUI
import WidgetKit

@main
struct UnpluggedWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ChargingLiveActivity()
    }
}

/// Same palette as the app (see UI/Theme.swift).
private enum WTheme {
    static let background = Color(red: 0x15 / 255, green: 0x15 / 255, blue: 0x1B / 255)
    static let violet = Color(red: 0xA7 / 255, green: 0x8B / 255, blue: 0xFA / 255)
    static let amber = Color(red: 0xE8 / 255, green: 0xB0 / 255, blue: 0x4E / 255)
    static let red = Color(red: 0xE5 / 255, green: 0x63 / 255, blue: 0x6A / 255)
    static let green = Color(red: 0x5B / 255, green: 0xC4 / 255, blue: 0x8A / 255)
    static let text = Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255)
    static let muted = Color(red: 0xA1 / 255, green: 0xA1 / 255, blue: 0xAA / 255)
}

private typealias ActivityState = ChargingActivityAttributes.ContentState

private extension ActivityState {
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
        case .grace: "car.fill"
        case .idle: "exclamationmark"
        case .ended: "checkmark"
        }
    }
}

private func euros(_ v: Double) -> String { String(format: "%.2f €", v) }

/// Picks the English or Lithuanian text for this activity.
private struct Copy {
    let lt: Bool
    init(_ attributes: ChargingActivityAttributes) { lt = attributes.lang == "lt" }
    func callAsFunction(_ en: String, _ ltText: String) -> String { lt ? ltText : en }
}

/// Live countdown that the system keeps running while the app is closed.
private struct Countdown: View {
    let state: ActivityState
    var body: some View {
        switch state.phase {
        case .charging:
            Text(timerInterval: state.chargeStart...state.chargeEnd, countsDown: true)
        case .grace:
            Text(timerInterval: state.chargeEnd...state.graceEnd, countsDown: true)
        case .idle:
            Text(String(format: "%.2f €/min", state.idleRateEurPerMin))
        case .ended:
            Text(euros(state.energyCostEur))
        }
    }
}

struct ChargingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChargingActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(WTheme.background.opacity(0.9))
                .activitySystemActionForegroundColor(WTheme.text)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("\(Int(context.state.soc.rounded())) %")
                    } icon: {
                        Image(systemName: context.state.symbol).foregroundStyle(context.state.color)
                    }
                    .font(.headline)
                    .foregroundStyle(WTheme.text)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: context.state)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(context.state.color)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    PhaseDetail(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                Image(systemName: context.state.symbol)
                    .foregroundStyle(context.state.color)
            } compactTrailing: {
                Countdown(state: context.state)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(context.state.color)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: context.state.symbol)
                    .foregroundStyle(context.state.color)
            }
            .keylineTint(context.state.color)
        }
    }
}

private struct LockScreenView: View {
    let attributes: ChargingActivityAttributes
    let state: ActivityState

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(state.color.opacity(0.18))
                Image(systemName: state.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(state.color)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(attributes.stationName)
                        .font(.headline)
                        .foregroundStyle(WTheme.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(attributes.connectorLabel)
                        .font(.caption)
                        .foregroundStyle(WTheme.muted)
                        .lineLimit(1)
                }
                PhaseDetail(attributes: attributes, state: state)
            }
        }
        .padding(16)
    }
}

/// Status line, countdown and progress for the current phase.
private struct PhaseDetail: View {
    let attributes: ChargingActivityAttributes
    let state: ActivityState

    var body: some View {
        let t = Copy(attributes)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title(t))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state.color)
                Spacer(minLength: 8)
                Countdown(state: state)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(WTheme.text)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            if state.phase == .charging {
                ProgressView(timerInterval: state.chargeStart...state.chargeEnd, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(state.color)
            }
            Text(subtitle(t))
                .font(.caption)
                .foregroundStyle(WTheme.muted)
                .lineLimit(2)
        }
    }

    private func title(_ t: Copy) -> String {
        switch state.phase {
        case .charging: t("Charging", "Kraunasi")
        case .grace: t("Charging complete", "Įkrovimas baigtas")
        case .idle: t("Idle fee is running", "Skaičiuojamas prastovos mokestis")
        case .ended: t("Session finished", "Įkrovimas užbaigtas")
        }
    }

    private func subtitle(_ t: Copy) -> String {
        let cost = euros(state.energyCostEur)
        switch state.phase {
        case .charging:
            return t("\(Int(state.soc.rounded())) % → \(Int(state.targetSoc)) % · \(cost) so far",
                     "\(Int(state.soc.rounded())) % → \(Int(state.targetSoc)) % · kol kas \(cost)")
        case .grace:
            return t("Move your car before the idle fee starts.",
                     "Patraukite automobilį, kol neprasidėjo prastovos mokestis.")
        case .idle:
            return t("Move your car — the rate keeps increasing.",
                     "Patraukite automobilį — tarifas didėja.")
        case .ended:
            return t("Thanks for freeing the spot.", "Ačiū, kad atlaisvinote vietą.")
        }
    }
}
