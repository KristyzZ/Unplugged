// Standalone macOS regression harness for the actual AppModel and domain files.
// System notification/ActivityKit adapters are replaced to avoid OS side effects.
import Foundation

enum AppTab { case explore, plan, charging, profile }

final class NotificationManager {
    static let shared = NotificationManager()
    static let chargeDoneId = "charge-done"
    static let graceOverId = "grace-over"
    static let moveCategory = "charging.move"
    static let holdReadyId = "hold-ready"
    static let holdEndingId = "hold-ending"
    static let holdCategory = "queue.hold"
    func cancel(_ ids: [String]) {}
    func schedule(id: String, title: String, body: String, after seconds: TimeInterval, category: String? = nil) {}
    func registerCategories() {}
}

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    func sync(session: ChargingSession?, enabled: Bool, simNow: Date, speed: Double, lang: Lang) {}
}

@main
struct AppModelPersistenceChecks {
    // This fixture deliberately preserves the original v1 flat schema, rather
    // than using the new feature payloads to generate their own migration input.
    struct LegacyState: Codable {
        var vehicleId: String
        var soc: Double
        var points: Int
        var lifetimePoints: Int
        var history: [PointsEntry]
        var session: ChargingSession?
        var queue: QueueEntry?
        var reports: [AbuseReport]
        var sessionHistory: [ChargingSession]?
        var defaultPaymentId: String?
        var activePlanIds: [String]?
        var simOffset: TimeInterval
        var lockScreen: Bool?
    }

    @MainActor
    static func main() throws {
        let defaults = UserDefaults.standard
        let keys = ["unplugged.state.v1", "unplugged.state.v2", "unplugged.lang"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
        let baseline = CommandLine.arguments.contains("--legacy-baseline")
        let initial = AppModel()
        let oldSession = initial.sessionHistory[0]
        let queue = QueueEntry(stationId: "europa", joinedAt: Date(timeIntervalSince1970: 100), position: 3)
        let fixture = LegacyState(
            vehicleId: "leaf", soc: 57, points: 321, lifetimePoints: 654,
            history: initial.history, session: oldSession, queue: queue,
            reports: initial.reports, sessionHistory: [oldSession], defaultPaymentId: "applepay",
            activePlanIds: ["enefit"], simOffset: 1234, lockScreen: false
        )
        let legacyData = try JSONEncoder().encode(fixture)
        defaults.set(legacyData, forKey: "unplugged.state.v1")
        let migrated = AppModel()
        precondition(migrated.vehicleId == "leaf" && migrated.soc == 57)
        precondition(migrated.points == 321 && migrated.lifetimePoints == 654)
        precondition(migrated.history == fixture.history && migrated.reports == fixture.reports)
        precondition(migrated.session == oldSession && migrated.sessionHistory == [oldSession])
        precondition(migrated.queue == queue && migrated.defaultPaymentId == "applepay")
        precondition(migrated.activePlanIds == ["enefit"] && !migrated.lockScreenEnabled)
        precondition(abs(migrated.simNow().timeIntervalSinceNow - 1234) < 2)
        print("PASS: all v1 fields, histories, session, queue, settings, and clock restored")

        // Older v1 saves omitted fields added after the original release.
        var oldObject = try JSONSerialization.jsonObject(with: legacyData) as! [String: Any]
        for key in ["sessionHistory", "defaultPaymentId", "activePlanIds", "lockScreen"] {
            oldObject.removeValue(forKey: key)
        }
        defaults.set(try JSONSerialization.data(withJSONObject: oldObject), forKey: "unplugged.state.v1")
        let older = AppModel()
        precondition(older.sessionHistory == initial.sessionHistory)
        precondition(older.defaultPaymentId == "visa" && older.activePlanIds == ["ignitis"])
        precondition(older.lockScreenEnabled)
        defaults.set(legacyData, forKey: "unplugged.state.v1")
        print("PASS: older v1 saves retain the original defaults for optional fields")

        migrated.setSoc(63)
        migrated.setVehicle("ioniq5")
        migrated.setDefaultPayment("visa")
        migrated.setPlan("ignitis", active: true)
        migrated.setLockScreen(false)
        migrated.joinQueue(migrated.stations[0])
        let savedQueue = migrated.queue
        let restored = AppModel()
        precondition(restored.soc == 63 && restored.vehicleId == "ioniq5")
        precondition(restored.defaultPaymentId == "visa" && restored.activePlanIds == ["ignitis", "enefit"])
        precondition(restored.queue == savedQueue && !restored.lockScreenEnabled)
        precondition(restored.session == oldSession && restored.reports == fixture.reports)
        if !baseline {
            precondition(defaults.data(forKey: "unplugged.state.v1") == legacyData)
            precondition(defaults.data(forKey: "unplugged.state.v2") != nil)
            // Once v2 exists it takes precedence over an older legacy snapshot.
            defaults.set(try JSONSerialization.data(withJSONObject: oldObject), forKey: "unplugged.state.v1")
            precondition(AppModel().soc == 63)
        }
        print(baseline ? "PASS: original persistence round-trip"
                       : "PASS: feature snapshots round-trip and v2 takes precedence without modifying v1")

        restored.resetDemo()
        restored.setLockScreen(false)
        var station = restored.stations[0]
        let index = station.connectors.firstIndex { Charging.isCompatible(restored.vehicle, $0) }!
        station.connectors[index].status = .available
        station.connectors[index].provenance = .demo(at: .now)
        let connector = station.connectors[index]
        let historyCount = restored.sessionHistory.count
        let originalPoints = restored.points
        restored.startCharging(at: station, connector: connector, targetSoc: 80)
        precondition(restored.hasActiveSession && restored.queue == nil)
        restored.stopCharging()
        precondition(restored.session?.doneAt != nil)
        restored.leaveSpot()
        precondition(!restored.hasActiveSession && restored.session?.endedAt != nil)
        // Moving at once earns 30; if drivers were waiting the spot is handed on, with a bonus.
        let handOverBonus = restored.session?.handedOver == true ? PointsReason.handedOver.points : 0
        precondition(restored.points == originalPoints + 30 + handOverBonus)
        restored.leaveSpot()
        precondition(restored.points == originalPoints + 30 + handOverBonus)
        restored.finishSession()
        precondition(restored.session == nil && restored.sessionHistory.count == historyCount + 1)
        let history = restored.sessionHistory
        restored.submitReport(station: station, kind: .other, connectorId: nil,
                              plate: "", description: "Regression check", hasPhoto: false)
        let reports = restored.reports
        precondition(AppModel().reports == reports && AppModel().sessionHistory == history)
        restored.joinQueue(station)
        restored.leaveQueue()
        precondition(AppModel().queue == nil)
        restored.setLang(.lt)
        precondition(restored.lang == .lt)
        restored.setLang(.en)
        precondition(restored.lang == .en)
        let beforeRedemption = restored.points
        precondition(restored.redeem(Points.rewards[0]))
        precondition(AppModel().points == beforeRedemption - Points.rewards[0].cost)
        restored.resetDemo()
        let reset = AppModel()
        precondition(reset.session == nil && reset.queue == nil && reset.points == 120)
        precondition(reset.vehicleId == "ioniq5" && reset.soc == 34)
        precondition(reset.reports == initial.reports && reset.history == initial.history)
        precondition(reset.sessionHistory == initial.sessionHistory && reset.activePlanIds == ["ignitis"])
        print("PASS: session start/stop/release/history, reports, queue, language, rewards, and reset")

        if !baseline {
            struct FutureProfile: Codable { var soc: Double; var futureFlag: Bool? }
            var snapshot = PersistenceSnapshot()
            try snapshot.set(FutureProfile(soc: 77, futureFlag: true), for: "profile")
            try snapshot.set(["newField": 1], for: "futureFeature")
            let roundTrip = try PersistenceSnapshot(data: snapshot.encoded())
            let value: FutureProfile? = roundTrip.value(for: "profile")
            precondition(value?.soc == 77 && value?.futureFlag == true)
            let absent: FutureProfile? = roundTrip.value(for: "missing")
            precondition(absent == nil)
            print("PASS: independent feature schemas and missing sections")
        }
    }
}
