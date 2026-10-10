import Foundation
import Observation

/// A full-screen moment shown over the app when a session changes state.
enum ChargingMoment: Equatable, Identifiable {
    /// Charging just started (plug-in animation).
    case started
    /// Charging reached the target, or was stopped early.
    case completed(stopped: Bool)
    /// The car left the spot: receipt and points.
    case finished

    var id: String {
        switch self {
        case .started: "started"
        case .completed: "completed"
        case .finished: "finished"
        }
    }
}

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
    /// Chargers held for a queued driver (you, or whoever is after you).
    var holds: [SpotHold] = []
    var reports: [AbuseReport] = AppModel.demoReports
    var sessionHistory: [ChargingSession] = AppModel.demoSessionHistory
    var defaultPaymentId = "visa"
    var activePlanIds: Set<String> = ["ignitis"]
    /// Show the charging Live Activity on the Lock Screen / Dynamic Island.
    var lockScreenEnabled = true
    /// The first-launch intro has been completed.
    var onboarded = false
    /// Usual charge limit (%): the default target when starting a charge and planning trips.
    var chargeLimit: Double = 80
    /// Chargers you rent out to other drivers.
    var hostListings: [HostListing] = []

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
    /// Full-screen animation currently shown, if any.
    var moment: ChargingMoment?
    /// Station page to open on the Explore tab (from the held-spot tile or the widget).
    var openStationId: String?
    /// Where "nearby" is measured from: your location, else Vilnius centre.
    var origin: LatLng = DemoData.vilniusCenter

    @ObservationIgnored var scheduledSessionNotificationIds: [String] = []
    @ObservationIgnored var realAnchor = Date()
    @ObservationIgnored var simAnchor = Date()
    @ObservationIgnored var graceAnnouncedFor: Date?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    /// Is another driver waiting for a spot at this station? A demo heuristic (a busy station); tests
    /// inject a fixed answer so results do not depend on the hour they run.
    @ObservationIgnored var someoneWaitingAt: (Station) -> Bool = { station in
        let hour = Calendar.current.component(.hour, from: .now)
        return station.freeCount == 0 || station.demandLevel(hour: hour) >= 0.5
    }

    #if os(iOS)
    @ObservationIgnored var lastWidgetSnapshot: NearbySnapshot?
    @ObservationIgnored var lastWidgetReload = Date.distantPast
    #endif

    var vehicle: Vehicle { DemoData.vehicle(vehicleId) }

    init(runLoops: Bool = true) {
        load()
        refreshStations()
        checkSession()
        if runLoops { startLoops() }
        rescheduleNotifications()
        #if os(iOS)
        listenForLockScreenActions()
        #endif
    }

    // MARK: Simulated clock

    func simNow() -> Date {
        simAnchor.addingTimeInterval(Date().timeIntervalSince(realAnchor) * speed)
    }

    /// The wall-clock time a simulated-clock moment will happen (demo speed-up aware).
    func realDate(_ sim: Date) -> Date {
        Date().addingTimeInterval(sim.timeIntervalSince(simNow()) / max(speed, 1))
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
        // Session events (charging finished, grace over), the queue and held spots.
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.checkSession()
                self?.checkQueueAndHolds()
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
