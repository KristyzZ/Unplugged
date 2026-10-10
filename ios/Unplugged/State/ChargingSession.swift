import Foundation

struct ChargingSession: Codable, Equatable {
    let stationId: String
    let stationName: String
    let connectorLabel: String
    /// Simulated-clock time the session started.
    let startedAt: Date
    let startSoc: Double
    let targetSoc: Double
    let minutesToTarget: Double
    let graceMinutes: Int
    let pricePerKwh: Double
    let batteryKwh: Double
    /// When charging finished or was stopped.
    var doneAt: Date?
    /// When the car left the spot.
    var endedAt: Date?
    var idleFeeEur: Double?
    var pointsEarned: Int?

    /// Optional for backward compatibility: old saves retain energy-only billing.
    let pricingTerms: Pricing.Terms?

    init(stationId: String, stationName: String, connectorLabel: String, startedAt: Date,
         startSoc: Double, targetSoc: Double, minutesToTarget: Double, graceMinutes: Int,
         pricePerKwh: Double, batteryKwh: Double, doneAt: Date? = nil, endedAt: Date? = nil,
         idleFeeEur: Double? = nil, pointsEarned: Int? = nil, pricingTerms: Pricing.Terms? = nil) {
        self.stationId = stationId
        self.stationName = stationName
        self.connectorLabel = connectorLabel
        self.startedAt = startedAt
        self.startSoc = startSoc
        self.targetSoc = targetSoc
        self.minutesToTarget = minutesToTarget
        self.graceMinutes = graceMinutes
        self.pricePerKwh = pricePerKwh
        self.batteryKwh = batteryKwh
        self.doneAt = doneAt
        self.endedAt = endedAt
        self.idleFeeEur = idleFeeEur
        self.pointsEarned = pointsEarned
        self.pricingTerms = pricingTerms
    }

    var scheduledDoneAt: Date { startedAt.addingTimeInterval(minutesToTarget * 60) }
}

/// Everything the UI needs to show a session at a given moment.
struct SessionSnapshot {
    enum Phase { case charging, grace, idle, ended }

    let phase: Phase
    let soc: Double
    let kwh: Double
    let energyCost: Double
    /// Charging subtotal (energy + start + charging time), excluding idle fees.
    let chargingCost: Double
    let pricingCharges: Pricing.Breakdown?
    let minutesLeft: Double
    let graceLeft: TimeInterval
    let idleMinutes: Double
    let idleFee: Double

    init(_ s: ChargingSession, now: Date) {
        let chargeEnd = s.doneAt ?? min(now, s.scheduledDoneAt)
        let progress = max(0, min(1, chargeEnd.timeIntervalSince(s.startedAt) / (s.minutesToTarget * 60)))
        let currentSoc = s.startSoc + (s.targetSoc - s.startSoc) * progress
        let energy = (currentSoc - s.startSoc) / 100 * s.batteryKwh / 0.92
        soc = currentSoc
        kwh = energy
        if let terms = s.pricingTerms {
            let minutes = max(0, min(s.minutesToTarget, chargeEnd.timeIntervalSince(s.startedAt) / 60))
            let charges = Pricing.charges(terms: terms, kwh: energy, chargingMinutes: minutes)
            pricingCharges = charges
            energyCost = charges.energy
            chargingCost = charges.total
        } else {
            pricingCharges = nil
            energyCost = energy * s.pricePerKwh
            chargingCost = energy * s.pricePerKwh
        }
        minutesLeft = max(0, s.scheduledDoneAt.timeIntervalSince(now) / 60)

        let ref = s.endedAt ?? now
        let sinceDone = s.doneAt.map { ref.timeIntervalSince($0) } ?? 0
        let graceSeconds = Double(s.graceMinutes) * 60
        let idle = s.doneAt == nil ? 0 : max(0, (sinceDone - graceSeconds) / 60)
        graceLeft = max(0, graceSeconds - sinceDone)
        idleMinutes = idle
        idleFee = s.idleFeeEur ?? IdleFee.fee(minutes: idle)

        if s.endedAt != nil { phase = .ended }
        else if s.doneAt == nil { phase = .charging }
        else if sinceDone < graceSeconds { phase = .grace }
        else { phase = .idle }
    }
}
