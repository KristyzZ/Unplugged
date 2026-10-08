import Foundation

// Rewards: responsible behaviour earns points that convert into discounts.

enum PointsReason: String, Codable, CaseIterable {
    case movedFast        // moved within 2 min of the "charging finished" notification
    case movedInGrace     // moved before the grace period ended
    case offPeak          // charged in a low-demand hour
    case reportConfirmed  // own abuse report verified
    case confirmReport    // helped verify someone else's report
    case redeem

    var points: Int {
        switch self {
        case .movedFast: 30
        case .movedInGrace: 20
        case .offPeak: 10
        case .reportConfirmed: 15
        case .confirmReport: 5
        case .redeem: 0
        }
    }

    var label: String {
        switch self {
        case .movedFast: tr("Car moved within 2 min")
        case .movedInGrace: tr("Car moved within the grace period")
        case .offPeak: tr("Charged off-peak")
        case .reportConfirmed: tr("Confirmed report")
        case .confirmReport: tr("Helped confirm a report")
        case .redeem: tr("Redeemed for a reward")
        }
    }

    static var earning: [PointsReason] { allCases.filter { $0 != .redeem } }
}

enum Points {
    /// Points for leaving the spot `minutesAfterDone` minutes after charging finished.
    static func forMove(minutesAfterDone: Double, graceMinutes: Int) -> PointsReason? {
        if minutesAfterDone <= 2 { return .movedFast }
        if minutesAfterDone <= Double(graceMinutes) { return .movedInGrace }
        return nil
    }

    struct Reward: Identifiable {
        let id: String
        let title: String
        let partner: String
        let cost: Int
    }

    static var rewards: [Reward] { [
        Reward(id: "coffee", title: tr("Free coffee"), partner: tr("Partner café"), cost: 80),
        Reward(id: "kwh-5", title: tr("−5 % on your next charge"), partner: "Unplugged", cost: 100),
        Reward(id: "eur-2", title: tr("€2 off charging"), partner: "Unplugged", cost: 200),
        Reward(id: "wash", title: tr("−50 % car wash"), partner: tr("Partner car wash"), cost: 250),
        Reward(id: "kwh-20", title: tr("−20 % on all charging for a week"), partner: "Unplugged", cost: 600),
    ] }

    struct Tier {
        let name: String
        let min: Int
    }

    static var tiers: [Tier] { [
        Tier(name: tr("Bronze"), min: 0),
        Tier(name: tr("Silver"), min: 300),
        Tier(name: tr("Gold"), min: 1000),
    ] }

    static func tier(for lifetime: Int) -> (current: Tier, next: Tier?) {
        let idx = tiers.lastIndex { lifetime >= $0.min } ?? 0
        return (tiers[idx], idx + 1 < tiers.count ? tiers[idx + 1] : nil)
    }
}
