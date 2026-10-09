import ActivityKit
import Foundation

// Shared between the app and the widget extension: what the Lock Screen /
// Dynamic Island charging Live Activity shows.

struct ChargingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case charging, grace, idle, ended
        }

        var phase: Phase
        /// Battery level when this state was sent (%).
        var soc: Double
        var startSoc: Double
        var targetSoc: Double
        /// Real (wall-clock) times, already adjusted for the demo time speed-up,
        /// so the system can run the bar and countdowns without the app.
        var chargeStart: Date
        var chargeEnd: Date
        var graceEnd: Date
        /// Average charging power (kW).
        var powerKw: Double
        /// Charging cost so far (€).
        var energyCostEur: Double
        /// What the whole session will cost at the target, or did cost once ended (€).
        var totalEur: Double
        var idleRateEurPerMin: Double
        var idleFeeEur: Double
        /// Points earned (ended) or the most you can still earn (grace).
        var points: Int
        /// Ended with the spot handed to the next driver. Optional so activities
        /// started by an older build still decode.
        var handedOver: Bool? = nil
    }

    /// Which session this activity belongs to (its start time), so a new
    /// session never reuses an old activity that's still on its way out.
    var sessionStart: Date
    var stationName: String
    var connectorLabel: String
    /// "en" or "lt" — the widget has no access to the app's language setting.
    var lang: String
}

extension ChargingActivityAttributes.ContentState {
    /// When this state stops being true without anyone updating it: charging
    /// turns into "move your car" at `chargeEnd`, and that into the idle fee at
    /// `graceEnd`. The system redraws the activity then, with `isStale` set,
    /// so the Lock Screen moves on even while the app is closed.
    var staleDate: Date? {
        switch phase {
        case .charging: chargeEnd
        case .grace: graceEnd
        case .idle, .ended: nil
        }
    }

    /// The phase to show, taking a passed stale date into account.
    func shownPhase(isStale: Bool) -> Phase {
        guard isStale else { return phase }
        switch phase {
        case .charging: return .grace
        case .grace: return .idle
        case .idle, .ended: return phase
        }
    }
}
