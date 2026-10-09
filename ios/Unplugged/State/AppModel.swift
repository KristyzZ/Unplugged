import Foundation
import Observation
import UIKit
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
    /// Your place in line; 1 = next.
    var position: Int
    /// Simulated-clock time the next car is expected to leave. Optional so
    /// older saved queues still decode.
    var nextEventAt: Date? = nil
}

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
    /// Chargers held for a queued driver (you, or whoever is after you).
    private(set) var holds: [SpotHold] = []
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
    /// Full-screen animation currently shown, if any.
    private(set) var moment: ChargingMoment?
    /// Station page to open on the Explore tab (from the held-spot tile).
    var openStationId: String?

    @ObservationIgnored private var realAnchor = Date()
    @ObservationIgnored private var simAnchor = Date()
    @ObservationIgnored private var graceAnnouncedFor: Date?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private let storageKey = "unplugged.state.v1"
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    var vehicle: Vehicle { DemoData.vehicle(vehicleId) }
    var hasActiveSession: Bool { session != nil && session?.endedAt == nil }
    /// A spot held for you right now.
    var myHold: SpotHold? { holds.first { $0.forMe } }

    init() {
        load()
        refreshStations()
        startLoops()
        rescheduleNotifications()
        // Buttons on the Lock Screen / Dynamic Island run in this process.
        ChargingActionInbox.handler = { [weak self] action in self?.handle(action) }
        takePendingAction()
    }

    // MARK: Lock Screen buttons

    /// An action pressed on the Live Activity while the app wasn't running.
    func takePendingAction() {
        if let action = ChargingActionInbox.take() { handle(action) }
    }

    private func handle(_ action: ChargingAction) {
        switch action {
        case .moved: leaveSpot()
        case .stop: stopCharging()
        case .releaseHold: releaseHold()
        }
    }

    // MARK: App in the background

    /// Live Activities can't change by themselves at an exact time, so when the
    /// app is sent away mid-session it asks for the usual ~30 s of background
    /// time. A phase change inside that window (charging done, free time over)
    /// still updates the Lock Screen right on time.
    func enteredBackground() {
        guard hasActiveSession, backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "charging-session") { [weak self] in
            self?.endBackgroundTime()
        }
        checkBackgroundTime()
    }

    func becameActive() {
        endBackgroundTime()
        takePendingAction()
        // Back while the car is due to move: show the session first.
        if let s = session, s.endedAt == nil, s.doneAt != nil {
            tab = .charging
        }
    }

    private func endBackgroundTime() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// Gives the background time back as soon as nothing will happen within it.
    private func checkBackgroundTime() {
        guard backgroundTask != .invalid else { return }
        guard let s = session, s.endedAt == nil else { return endBackgroundTime() }
        let done = s.doneAt ?? s.scheduledDoneAt
        let graceEnd = done.addingTimeInterval(Double(s.graceMinutes) * 60)
        let next = [done, graceEnd].map(realDate).filter { $0 > Date() }.min()
        let remaining = UIApplication.shared.backgroundTimeRemaining
        if next == nil || next!.timeIntervalSinceNow > remaining - 2 {
            endBackgroundTime()
        }
    }

    // MARK: Moments

    func dismissMoment() {
        moment = nil
    }

    // MARK: Language

    func setLang(_ value: Lang) {
        guard value != lang else { return }
        L10n.set(value)
        lang = value
        NotificationManager.shared.registerCategories()
        refreshStations()
        banners.removeAll()
        rescheduleNotifications()
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
        // Session events (charging finished, grace over).
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.checkSession()
                self?.checkQueueAndHolds()
            }
        })
    }

    private func checkSession() {
        defer { checkBackgroundTime() }
        guard var s = session, s.endedAt == nil else { return }
        let now = simNow()
        if s.doneAt == nil && now >= s.scheduledDoneAt {
            s.doneAt = s.scheduledDoneAt
            session = s
            save()
            syncLiveActivity()
            moment = .completed(stopped: false)
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
            batteryKwh: vehicle.batteryKwh,
            connectorId: connector.id
        )
        if myHold?.stationId == station.id {
            holds.removeAll { $0.forMe }
            refreshStations()
        }
        queue = nil
        graceAnnouncedFor = nil
        tileHiddenFor = nil
        moment = .started
        rescheduleNotifications()
        save()
    }

    func stopCharging() {
        guard var s = session, s.doneAt == nil else { return }
        s.doneAt = simNow()
        session = s
        rescheduleNotifications()
        save()
        moment = .completed(stopped: true)
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
        let handOver = handOverSpot(s, at: now)
        // The handover bonus is for moving on time; an overstay still hands the
        // spot on, but earns nothing.
        let handOverBonus = handOver && reason != nil
        s.handedOver = handOver
        s.pointsEarned = (reason?.points ?? 0) + (handOverBonus ? PointsReason.handedOver.points : 0)
        session = s
        soc = SessionSnapshot(s, now: now).soc.rounded()
        if let reason {
            addPoints(reason, note: s.stationName)
        }
        if handOverBonus {
            addPoints(.handedOver, note: s.stationName)
        }
        // The receipt shows the points, so no banner here.
        moment = .finished
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
        moment = nil
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
        rescheduleQueueNotifications()
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
                after: done.timeIntervalSince(now) / speed,
                category: NotificationManager.moveCategory
            )
        }
        let graceEnd = done.addingTimeInterval(Double(s.graceMinutes) * 60)
        if graceEnd > now {
            n.schedule(
                id: NotificationManager.graceOverId,
                title: tr("Idle fee has started"),
                body: tr("Move your car from \(s.stationName) — the rate is increasing."),
                after: graceEnd.timeIntervalSince(now) / speed,
                category: NotificationManager.moveCategory
            )
        }
    }

    // MARK: Queue and held spots

    /// Station snapshot with the held chargers marked.
    private func refreshStations() {
        var fresh = DemoData.stations(at: .now, tick: tick)
        for hold in holds {
            guard let si = fresh.firstIndex(where: { $0.id == hold.stationId }),
                  let ci = fresh[si].connectors.firstIndex(where: { $0.id == hold.connectorId }) else { continue }
            fresh[si].connectors[ci].status = .reserved
            fresh[si].connectors[ci].idleMinutes = nil
            fresh[si].connectors[ci].etaMinutes = nil
        }
        stations = fresh
    }

    func joinQueue(_ station: Station) {
        let hour = Calendar.current.component(.hour, from: .now)
        // Busier station, more people ahead (1–3). The first car is due when the
        // soonest charging session there is expected to end.
        let position = 1 + min(2, Int(station.demandLevel(hour: hour) * 3))
        let soonest = Double(station.connectors.compactMap(\.etaMinutes).min() ?? 8)
        queue = QueueEntry(
            stationId: station.id, joinedAt: .now, position: position,
            nextEventAt: simNow().addingTimeInterval(min(15, max(3, soonest)) * 60)
        )
        save()
        rescheduleQueueNotifications()
        showBanner(tr("You joined the queue"), tr("\(station.name): we'll hold the next free spot for you."))
    }

    func leaveQueue() {
        queue = nil
        save()
        rescheduleQueueNotifications()
    }

    /// Give up the spot held for you; it goes to the next driver.
    func releaseHold() {
        guard myHold != nil else { return }
        holds.removeAll { $0.forMe }
        refreshStations()
        save()
        rescheduleQueueNotifications()
        showBanner(tr("Spot released"), tr("It goes to the next driver in line."))
    }

    func openStation(_ id: String) {
        tab = .explore
        openStationId = id
    }

    /// The car left: if someone is waiting here, keep this charger for them.
    private func handOverSpot(_ s: ChargingSession, at now: Date) -> Bool {
        guard let station = stations.first(where: { $0.id == s.stationId }) else { return false }
        let hour = Calendar.current.component(.hour, from: .now)
        let someoneWaiting = station.freeCount == 0 || station.demandLevel(hour: hour) >= 0.5
        guard someoneWaiting else { return false }
        let connector = station.connectors.first { $0.id == s.connectorId } ?? station.connectors[0]
        holds.removeAll { $0.id == "\(station.id)|\(connector.id)" }
        holds.append(SpotHold(
            stationId: station.id, stationName: station.name, connectorId: connector.id,
            connectorLabel: "\(connector.type.label) · \(Int(connector.powerKw)) kW",
            startedAt: now, until: now.addingTimeInterval(SpotHold.minutes * 60), forMe: false
        ))
        refreshStations()
        return true
    }

    /// Moves the queue along and lets holds run out. Runs with the session loop.
    private func checkQueueAndHolds() {
        let now = simNow()

        let expired = holds.filter { $0.until <= now }
        if !expired.isEmpty {
            holds.removeAll { $0.until <= now }
            refreshStations()
            save()
            if expired.contains(where: \.forMe) {
                rescheduleQueueNotifications()
                showBanner(tr("Your held spot was passed on"), tr("The \(Int(SpotHold.minutes)) minutes ran out, so it went to the next driver."))
            }
        }

        guard var q = queue, myHold == nil, let next = q.nextEventAt, now >= next else { return }
        guard let station = stations.first(where: { $0.id == q.stationId }) else {
            queue = nil
            return
        }
        if q.position > 1 {
            // A car left, but someone ahead of you gets that spot.
            q.position -= 1
            q.nextEventAt = next.addingTimeInterval(Double(3 + 2 * q.position) * 60)
            queue = q
            save()
            rescheduleQueueNotifications()
            showBanner(tr("You moved up"), q.position == 1 ? tr("You're next at \(station.name).") : tr("\(q.position) in line at \(station.name)."))
            return
        }

        // Your turn: the charger that just freed up is held for you.
        let vehicle = self.vehicle
        let usable = station.connectors.filter { Charging.isCompatible(vehicle, $0) && $0.status != .offline }
        let connector = usable.first { [.charging, .idle, .blocked].contains($0.status) } ?? usable.first ?? station.connectors[0]
        holds.removeAll { $0.connectorId == connector.id }
        holds.append(SpotHold(
            stationId: station.id, stationName: station.name, connectorId: connector.id,
            connectorLabel: "\(connector.type.label) · \(Int(connector.powerKw)) kW",
            startedAt: next, until: next.addingTimeInterval(SpotHold.minutes * 60), forMe: true
        ))
        queue = nil
        refreshStations()
        save()
        rescheduleQueueNotifications()
        showBanner(tr("A spot is held for you"), tr("\(station.name): it's yours for \(Int(SpotHold.minutes)) min."))
    }

    /// "Spot held for you" when your turn comes, and a reminder a minute
    /// before a held spot is passed on. Both work with the app closed.
    private func rescheduleQueueNotifications() {
        let n = NotificationManager.shared
        n.cancel([NotificationManager.holdReadyId, NotificationManager.holdEndingId])
        let now = simNow()
        if let q = queue, q.position == 1, let next = q.nextEventAt, next > now,
           let station = stations.first(where: { $0.id == q.stationId }) {
            n.schedule(
                id: NotificationManager.holdReadyId,
                title: tr("A spot is held for you"),
                body: tr("\(station.name): it's yours for \(Int(SpotHold.minutes)) min."),
                after: next.timeIntervalSince(now) / speed,
                category: NotificationManager.holdCategory
            )
        }
        if let hold = myHold, hold.until.timeIntervalSince(now) > 90 {
            n.schedule(
                id: NotificationManager.holdEndingId,
                title: tr("1 min left on your spot"),
                body: tr("\(hold.stationName): start charging or it goes to the next driver."),
                after: (hold.until.timeIntervalSince(now) - 60) / speed,
                category: NotificationManager.holdCategory
            )
        }
    }

    // MARK: Reports

    func submitReport(station: Station, kind: ReportKind, connectorId: String?, plate: String, description: String,
                      hasPhoto: Bool, plateFromPhoto: Bool = false) {
        // The charger's own data backs the report, judged from its live state now:
        // wrong use → is that spot occupied without a session? (all spots when
        // the driver isn't sure); charger problem → does it show as out of service?
        let evidence: StationEvidence?
        let telemetry: Bool
        switch kind {
        case .wrongUsage:
            let spot = station.connectors.first { $0.id == connectorId }
            let found = spot.map { StationEvidence($0.status) } ?? StationEvidence(station: station)
            evidence = found
            telemetry = found == .occupiedNoSession
        case .chargerProblem:
            let scope = station.connectors.filter { connectorId == nil || $0.id == connectorId }
            evidence = nil
            telemetry = scope.contains { $0.status == .offline }
        case .other:
            evidence = nil
            telemetry = false
        }
        let report = AbuseReport(
            stationId: station.id,
            plate: kind == .wrongUsage ? Reports.formatPlate(plate) : "",
            description: description,
            hasPhoto: hasPhoto,
            telemetryMatches: telemetry,
            confirmations: 0,
            createdAt: .now,
            byMe: true,
            kind: kind,
            connectorId: kind == .other ? nil : connectorId,
            plateFromPhoto: kind == .wrongUsage ? plateFromPhoto : nil,
            evidence: evidence
        )
        reports.insert(report, at: 0)
        save()
        if kind != .wrongUsage {
            showBanner(tr("Report sent"), tr("Thanks — we'll pass it on to the operator."))
        } else if report.isConfirmed {
            addPoints(.reportConfirmed, note: station.name)
            let why = report.stationEvidence == .occupiedNoSession
                ? tr("The charger confirms the spot is blocked.")
                : tr("Photo, plate and charger data agree.")
            showBanner(tr("Report confirmed"), why + " " + tr("+\(PointsReason.reportConfirmed.points) pts"))
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
        moment = nil
        queue = nil
        holds = []
        refreshStations()
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
        var holds: [SpotHold]?
    }

    private func save() {
        let state = Persisted(
            vehicleId: vehicleId, soc: soc, points: points, lifetimePoints: lifetimePoints,
            history: history, session: session, queue: queue, reports: reports,
            sessionHistory: sessionHistory, defaultPaymentId: defaultPaymentId, activePlanIds: Array(activePlanIds),
            simOffset: simNow().timeIntervalSinceNow,
            lockScreen: lockScreenEnabled,
            holds: holds
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
        holds = s.holds ?? []
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
