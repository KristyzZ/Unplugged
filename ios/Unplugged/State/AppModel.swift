import Foundation
import Observation

/// App state for the prototype. This is the only @Observable state container.
/// Feature behavior and Codable payloads live in AppModel+<Feature>.swift.
/// Cross-file extensions need internal setters/helpers (Swift private and
/// private(set) do not span files). Views read these properties and mutate state
/// through feature methods. Navigation and banner state remain directly
/// bindable as before; other feature state is read-only outside State by convention.
/// Keep feature payload changes in their owning file, not a shared schema.
@MainActor
@Observable
final class AppModel {
    // MARK: Persisted
    var vehicleId = "ioniq5"
    var soc: Double = 34
    var points = 120
    var lifetimePoints = 240
    var history: [PointsEntry] = AppModel.demoHistory
    var session: ChargingSession?
    var sessionEvents: [SessionEvent] = []
    var queue: QueueEntry?
    var reports: [AbuseReport] = AppModel.demoReports
    var sessionHistory: [ChargingSession] = AppModel.demoSessionHistory
    var defaultPaymentId = "visa"
    var activePlanIds: Set<String> = ["ignitis"]
    /// Show the charging Live Activity on the Lock Screen / Dynamic Island.
    var lockScreenEnabled = true

    // MARK: Live
    var lang: Lang = L10n.current
    var tab: AppTab = .explore
    /// The charging tile was closed with × during this phase; it comes back on the next one.
    var tileHiddenFor: SessionSnapshot.Phase?
    var stations: [Station] = []
    var tick = 0
    /// Demo time multiplier for the charging simulation (1 = real time).
    var speed: Double = 1
    var banners: [Banner] = []

    @ObservationIgnored var scheduledSessionNotificationIds: [String] = []
    @ObservationIgnored var realAnchor = Date()
    @ObservationIgnored var simAnchor = Date()
    @ObservationIgnored var graceAnnouncedFor: Date?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    var vehicle: Vehicle { DemoData.vehicle(vehicleId) }

    init(runLoops: Bool = true) {
        load()
        refreshStations()
        checkSession()
        if runLoops { startLoops() }
        rescheduleNotifications()
    }

    // MARK: Simulated clock

    func simNow() -> Date {
        simAnchor.addingTimeInterval(Date().timeIntervalSince(realAnchor) * speed)
    }

    func setSpeed(_ value: Double) {
        let now = simNow()
        realAnchor = Date()
        simAnchor = now
        speed = value
        rescheduleNotifications()
        save()
    }

    // MARK: Loops

    private func startLoops() {
        // "Real-time" station updates every 20 s.
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard let self else { return }
                self.tick += 1
                self.refreshStations()
            }
        })
        // Session events (charging finished, grace over).
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.checkSession()
            }
        })
    }

    // MARK: Clock persistence

    private struct ClockState: Codable {
        var simOffset: TimeInterval
    }

    func saveClock(to snapshot: inout PersistenceSnapshot) throws {
        try snapshot.set(ClockState(simOffset: simNow().timeIntervalSinceNow), for: "clock")
    }

    func loadClock(from snapshot: PersistenceSnapshot) {
        guard let state: ClockState = snapshot.value(for: "clock") else { return }
        realAnchor = Date()
        simAnchor = Date().addingTimeInterval(state.simOffset)
    }
}
