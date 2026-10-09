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
        var targetSoc: Double
        /// Real (wall-clock) times, already adjusted for the demo time speed-up,
        /// so the system can run the countdowns without the app.
        var chargeStart: Date
        var chargeEnd: Date
        var graceEnd: Date
        var energyCostEur: Double
        var idleRateEurPerMin: Double
    }

    var stationName: String
    var connectorLabel: String
    /// "en" or "lt" — the widget has no access to the app's language setting.
    var lang: String
}
