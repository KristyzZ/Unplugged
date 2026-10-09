import AppIntents
import Foundation

// Buttons on the charging Live Activity (Lock Screen and Dynamic Island).
// Live Activity intents always run in the app's process, even when the app
// isn't open: iOS launches it in the background, `perform()` runs, and the
// Live Activity is updated from there.

enum ChargingAction: String {
    case moved, stop
}

/// Hands Live Activity button presses to the app. When the app's model is
/// running it handles them at once; otherwise the press is kept until it is.
enum ChargingActionInbox {
    private static let key = "unplugged.pendingChargingAction"

    @MainActor static var handler: ((ChargingAction) -> Void)?

    @MainActor static func deliver(_ action: ChargingAction) {
        if let handler {
            handler(action)
        } else {
            UserDefaults.standard.set(action.rawValue, forKey: key)
        }
    }

    /// A press that arrived before the app's model existed.
    static func take() -> ChargingAction? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        return ChargingAction(rawValue: raw)
    }
}

struct MovedCarIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "I moved my car"
    static let description: IntentDescription? = IntentDescription("Frees the charging spot and ends the session.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        ChargingActionInbox.deliver(.moved)
        return .result()
    }
}

struct StopChargingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop charging"
    static let description: IntentDescription? = IntentDescription("Stops charging at the current battery level.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        ChargingActionInbox.deliver(.stop)
        return .result()
    }
}
