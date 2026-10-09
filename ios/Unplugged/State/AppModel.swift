import Foundation
import Observation
import SwiftUI

struct PointsEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    let reason: PointsReason
    let points: Int
    let at: Date
    var note: String?
}

struct QueueEntry: Codable, Equatable {
    let stationId: String
    let joinedAt: Date
    var position: Int
}

struct Banner: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let body: String?
}

/// App state for the prototype (no backend yet). Persisted to UserDefaults so
/// relaunching the app during a demo keeps the session, points and reports.
@MainActor
@Observable
final class AppModel {
    // MARK: Persisted
    private(set) var vehicleId = "ioniq5"
    private(set) var soc: Double = 34
    private(set) var points = 120
    private(set) var lifetimePoints = 240
    private(set) var history: [PointsEntry] = AppModel.demoHistory
    private(set) var session: ChargingSession?
    private(set) var queue: QueueEntry?
    private(set) var reports: [AbuseReport] = AppModel.demoReports
    private(set) var sessionHistory: [ChargingSession] = AppModel.demoSessionHistory
    private(set) var defaultPaymentId = "visa"
    private(set) var activePlanIds: Set<String> = ["ignitis"]
    /// Show the charging Live Activity on the Lock Screen / Dynamic Island.
    private(set) var lockScreenEnabled = true

    // MARK: Live
    private(set) var lang: Lang = L10n.current
    var tab: AppTab = .explore
    /// The charging tile was closed with × during this phase; it comes back on the next one.
    private(set) var tileHiddenFor: SessionSnapshot.Phase?
    private(set) var stations: [Station] = []
    private(set) var tick = 0
    /// Demo time multiplier for the charging simulation (1 = real time).
    private(set) var speed: Double = 1
    var banners: [Banner] = []

    @ObservationIgnored private var realAnchor = Date()
    @ObservationIgnored private var simAnchor = Date()
    @ObservationIgnored private var graceAnnouncedFor: Date?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private let storageKey = "unplugged.state.v1"

    var vehicle: Vehicle { DemoData.vehicle(vehicleId) }
    var hasActiveSession: Bool { session != nil && session?.endedAt == nil }

    init() {
        load()
        stations = DemoData.stations(at: .now, tick: tick)
        startLoops()
        rescheduleNotifications()
    }

    // MARK: Language

    func setLang(_ value: Lang) {
        guard value != lang else { return }
        L10n.set(value)
        lang = value
        stations = DemoData.stations(at: .now, tick: tick)
        banners.removeAll()
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
                self.stations = DemoData.stations(at: .now, tick: self.tick)
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

    private func checkSession() {
        guard var s = session, s.endedAt == nil else { return }
        let now = simNow()
        if s.doneAt == nil && now >= s.scheduledDoneAt {
            s.doneAt = s.scheduledDoneAt
            session = s
            save()
            syncLiveActivity()
            showBanner(tr("Charging complete"), tr("You have \(s.graceMinutes) min to move your car. After that an idle fee applies."))
        }
        if let done = s.doneAt, graceAnnouncedFor != done, now >= done.addingTimeInterval(Double(s.graceMinutes) * 60) {
            graceAnnouncedFor = done
            syncLiveActivity()
            showBanner(tr("Idle fee has started"), tr("The longer you stay, the higher the rate."))
        }
    }

    // MARK: Vehicle

    func setVehicle(_ id: String) {
        vehicleId = id
        save()
    }

    func setSoc(_ value: Double) {
        soc = min(100, max(1, value.rounded()))
        save()
    }

    // MARK: Points

    func addPoints(_ reason: PointsReason, note: String? = nil) {
        points += reason.points
        lifetimePoints += reason.points
        history.insert(PointsEntry(reason: reason, points: reason.points, at: .now, note: note), at: 0)
        save()
    }

    @discardableResult
    func redeem(_ reward: Points.Reward) -> Bool {
        guard points >= reward.cost else { return false }
        points -= reward.cost
        history.insert(PointsEntry(reason: .redeem, points: -reward.cost, at: .now, note: reward.title), at: 0)
        save()
        showBanner(tr("Reward activated"), reward.title)
        return true
    }

    // MARK: Charging

    func startCharging(at station: Station, connector: Connector, targetSoc: Double) {
        let estimate = Charging.chargeTime(vehicle, connector, from: soc, to: targetSoc)
        let hour = Calendar.current.component(.hour, from: .now)
        session = ChargingSession(
            stationId: station.id,
            stationName: station.name,
            connectorLabel: "\(connector.type.rawValue) · \(Int(connector.powerKw)) kW",
            startedAt: simNow(),
            startSoc: soc,
            targetSoc: targetSoc,
            minutesToTarget: Double(max(1, estimate.minutes)),
            graceMinutes: IdleFee.graceMinutes(demand: station.demandLevel(hour: hour)),
            pricePerKwh: station.pricePerKwh,
            batteryKwh: vehicle.batteryKwh
        )
        queue = nil
        graceAnnouncedFor = nil
        tileHiddenFor = nil
        rescheduleNotifications()
        save()
    }

    func stopCharging() {
        guard var s = session, s.doneAt == nil else { return }
        s.doneAt = simNow()
        session = s
        rescheduleNotifications()
        save()
        showBanner(tr("Charging stopped"), tr("You have \(s.graceMinutes) min to move your car."))
    }

    /// The driver has moved the car: settle the idle fee and award points.
    func leaveSpot() {
        guard var s = session, s.endedAt == nil else { return }
        let now = simNow()
        let done = s.doneAt ?? now
        let minutesAfter = now.timeIntervalSince(done) / 60
        let idle = max(0, minutesAfter - Double(s.graceMinutes))
        s.doneAt = done
        s.endedAt = now
        s.idleFeeEur = IdleFee.fee(minutes: idle)
        let reason = Points.forMove(minutesAfterDone: minutesAfter, graceMinutes: s.graceMinutes)
        s.pointsEarned = reason?.points ?? 0
        session = s
        soc = SessionSnapshot(s, now: now).soc.rounded()
        if let reason {
            addPoints(reason, note: s.stationName)
            showBanner(tr("+\(reason.points) pts"), reason.label)
        }
        NotificationManager.shared.cancel([NotificationManager.chargeDoneId, NotificationManager.graceOverId])
        save()
        syncLiveActivity()
    }

    func finishSession() {
        if let s = session, s.endedAt != nil {
            sessionHistory.insert(s, at: 0)
            sessionHistory = Array(sessionHistory.prefix(30))
        }
        session = nil
        tileHiddenFor = nil
        save()
        syncLiveActivity()
    }

    // MARK: Lock Screen

    func setLockScreen(_ on: Bool) {
        lockScreenEnabled = on
        save()
        syncLiveActivity()
    }

    private func syncLiveActivity() {
        LiveActivityManager.shared.sync(
            session: session,
            enabled: lockScreenEnabled,
            simNow: simNow(),
            speed: speed,
            lang: lang
        )
    }

    /// × on the charging tile. A finished session is closed for good;
    /// otherwise the tile hides until the next phase.
    func hideTile() {
        guard let s = session else { return }
        let phase = SessionSnapshot(s, now: simNow()).phase
        if phase == .ended {
            finishSession()
        } else {
            tileHiddenFor = phase
        }
    }

    // MARK: Profile

    func setDefaultPayment(_ id: String) {
        defaultPaymentId = id
        save()
    }

    func setPlan(_ operatorId: String, active: Bool) {
        if active { activePlanIds.insert(operatorId) } else { activePlanIds.remove(operatorId) }
        save()
    }

    private func rescheduleNotifications() {
        syncLiveActivity()
        let n = NotificationManager.shared
        n.cancel([NotificationManager.chargeDoneId, NotificationManager.graceOverId])
        guard let s = session, s.endedAt == nil else { return }
        let now = simNow()
        let done = s.doneAt ?? s.scheduledDoneAt
        if s.doneAt == nil, done > now {
            n.schedule(
                id: NotificationManager.chargeDoneId,
                title: tr("Charging complete"),
                body: tr("\(s.stationName): you have \(s.graceMinutes) min to move your car."),
                after: done.timeIntervalSince(now) / speed
            )
        }
        let graceEnd = done.addingTimeInterval(Double(s.graceMinutes) * 60)
        if graceEnd > now {
            n.schedule(
                id: NotificationManager.graceOverId,
                title: tr("Idle fee has started"),
                body: tr("Move your car from \(s.stationName) — the rate is increasing."),
                after: graceEnd.timeIntervalSince(now) / speed
            )
        }
    }

    // MARK: Queue

    func joinQueue(_ station: Station) {
        queue = QueueEntry(stationId: station.id, joinedAt: .now, position: 2)
        save()
        showBanner(tr("You joined the queue"), tr("\(station.name): we'll notify you when a spot frees up."))
    }

    func leaveQueue() {
        queue = nil
        save()
    }

    // MARK: Reports

    func submitReport(station: Station, kind: ReportKind, connectorId: String?, plate: String, description: String, hasPhoto: Bool) {
        // Station telemetry backs the report: a bay occupied without a session
        // (wrong use), or a connector the station already shows as out of service.
        let telemetry: Bool
        switch kind {
        case .wrongUsage:
            telemetry = station.connectors.contains { $0.status == .blocked }
        case .chargerProblem:
            let scope = station.connectors.filter { connectorId == nil || $0.id == connectorId }
            telemetry = scope.contains { $0.status == .offline }
        case .other:
            telemetry = false
        }
        let report = AbuseReport(
            stationId: station.id,
            plate: kind == .wrongUsage ? plate.uppercased() : "",
            description: description,
            hasPhoto: hasPhoto,
            telemetryMatches: telemetry,
            confirmations: 0,
            createdAt: .now,
            byMe: true,
            kind: kind,
            connectorId: kind == .chargerProblem ? connectorId : nil
        )
        reports.insert(report, at: 0)
        save()
        if kind != .wrongUsage {
            showBanner(tr("Report sent"), tr("Thanks — we'll pass it on to the operator."))
        } else if report.isConfirmed {
            addPoints(.reportConfirmed, note: station.name)
            showBanner(tr("Report confirmed"), tr("Station data confirmed the violation. +\(PointsReason.reportConfirmed.points) pts"))
        } else {
            showBanner(tr("Report sent"), tr("Waiting for more confirmations."))
        }
    }

    func confirmReport(_ id: String) {
        guard let i = reports.firstIndex(where: { $0.id == id }) else { return }
        reports[i].confirmations += 1
        guard reports[i].category == .wrongUsage else {
            showBanner(tr("Thanks!"), tr("Your confirmation helps the operator prioritize."))
            return
        }
        let name = stations.first { $0.id == reports[i].stationId }?.name
        addPoints(.confirmReport, note: name)
        showBanner(tr("+\(PointsReason.confirmReport.points) pts"), tr("Thanks for helping to confirm."))
    }

    func confirmedOffences(forPlate plate: String) -> Int {
        let p = Reports.normalizePlate(plate)
        return reports.filter { Reports.normalizePlate($0.plate) == p && $0.isConfirmed }.count
    }

    // MARK: Banners

    func showBanner(_ title: String, _ body: String? = nil) {
        let banner = Banner(title: title, body: body)
        banners.append(banner)
        AccessibilityNotification.Announcement([title, body].compactMap { $0 }.joined(separator: ". ")).post()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.banners.removeAll { $0.id == banner.id }
        }
    }

    // MARK: Demo reset

    func resetDemo() {
        vehicleId = "ioniq5"
        soc = 34
        points = 120
        lifetimePoints = 240
        history = AppModel.demoHistory
        session = nil
        tileHiddenFor = nil
        queue = nil
        reports = AppModel.demoReports
        sessionHistory = AppModel.demoSessionHistory
        defaultPaymentId = "visa"
        activePlanIds = ["ignitis"]
        realAnchor = Date()
        simAnchor = Date()
        speed = 1
        rescheduleNotifications()
        save()
    }

    // MARK: Persistence

    private struct Persisted: Codable {
        var vehicleId: String
        var soc: Double
        var points: Int
        var lifetimePoints: Int
        var history: [PointsEntry]
        var session: ChargingSession?
        var queue: QueueEntry?
        var reports: [AbuseReport]
        // Added later; optional so older saved state still decodes.
        var sessionHistory: [ChargingSession]?
        var defaultPaymentId: String?
        var activePlanIds: [String]?
        /// Simulated clock offset (sim − real) so a sped-up session survives relaunch.
        var simOffset: TimeInterval
        var lockScreen: Bool?
    }

    private func save() {
        let state = Persisted(
            vehicleId: vehicleId, soc: soc, points: points, lifetimePoints: lifetimePoints,
            history: history, session: session, queue: queue, reports: reports,
            sessionHistory: sessionHistory, defaultPaymentId: defaultPaymentId, activePlanIds: Array(activePlanIds),
            simOffset: simNow().timeIntervalSinceNow,
            lockScreen: lockScreenEnabled
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let s = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        vehicleId = s.vehicleId
        soc = s.soc
        points = s.points
        lifetimePoints = s.lifetimePoints
        history = s.history
        session = s.session
        queue = s.queue
        reports = s.reports
        sessionHistory = s.sessionHistory ?? AppModel.demoSessionHistory
        defaultPaymentId = s.defaultPaymentId ?? "visa"
        activePlanIds = Set(s.activePlanIds ?? ["ignitis"])
        lockScreenEnabled = s.lockScreen ?? true
        realAnchor = Date()
        simAnchor = Date().addingTimeInterval(s.simOffset)
    }

    // MARK: Demo seed data

    private static let demoHistory: [PointsEntry] = [
        PointsEntry(reason: .movedFast, points: 30, at: Date().addingTimeInterval(-2 * 86_400)),
        PointsEntry(reason: .offPeak, points: 10, at: Date().addingTimeInterval(-2 * 86_400)),
    ]

    private static let demoSessionHistory: [ChargingSession] = {
        let now = Date()
        func entry(_ id: String, _ name: String, _ connector: String, daysAgo: Double, charge: Double,
                   idle: Double, grace: Int, price: Double, from: Double, to: Double, kwh: Double, points: Int) -> ChargingSession {
            let start = now.addingTimeInterval(-daysAgo * 86_400)
            let done = start.addingTimeInterval(charge * 60)
            return ChargingSession(
                stationId: id, stationName: name, connectorLabel: connector, startedAt: start,
                startSoc: from, targetSoc: to, minutesToTarget: charge, graceMinutes: grace,
                pricePerKwh: price, batteryKwh: kwh,
                doneAt: done, endedAt: done.addingTimeInterval((Double(grace) + idle) * 60),
                idleFeeEur: IdleFee.fee(minutes: idle), pointsEarned: points
            )
        }
        return [
            entry("akropolis", "Akropolis", "CCS2 · 150 kW", daysAgo: 2, charge: 32, idle: 0, grace: 10, price: 0.59, from: 22, to: 80, kwh: 77, points: 30),
            entry("ozas", "Ozas", "CCS2 · 120 kW", daysAgo: 6, charge: 41, idle: 12, grace: 8, price: 0.55, from: 18, to: 85, kwh: 77, points: 0),
        ]
    }()

    private static let demoReports: [AbuseReport] = [
        AbuseReport(
            id: "r-demo", stationId: "europa", plate: "KLM 482",
            description: "A petrol car has been parked in the charging spot since morning.",
            hasPhoto: true, telemetryMatches: false, confirmations: 1,
            createdAt: Date().addingTimeInterval(-3600), byMe: false
        ),
        AbuseReport(
            id: "r-demo-2", stationId: "europa", plate: "",
            description: "The first connector won't start a session.",
            hasPhoto: false, telemetryMatches: false, confirmations: 2,
            createdAt: Date().addingTimeInterval(-7200), byMe: false,
            kind: .chargerProblem
        ),
    ]
}
