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
        case .movedFast: "Automobilis patrauktas per 2 min."
        case .movedInGrace: "Automobilis patrauktas per „grace period“"
        case .offPeak: "Įkrovimas ne piko metu"
        case .reportConfirmed: "Patvirtintas pranešimas"
        case .confirmReport: "Padėjote patvirtinti pranešimą"
        case .redeem: "Iškeista į privalumą"
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

    static let rewards: [Reward] = [
        Reward(id: "coffee", title: "Nemokama kava", partner: "Partnerio kavinė", cost: 80),
        Reward(id: "kwh-5", title: "−5 % kitam įkrovimui", partner: "Unplugged", cost: 100),
        Reward(id: "eur-2", title: "2 € įkrovimo nuolaida", partner: "Unplugged", cost: 200),
        Reward(id: "wash", title: "−50 % automobilio plovimui", partner: "Partnerio plovykla", cost: 250),
        Reward(id: "kwh-20", title: "−20 % visiems įkrovimams savaitę", partner: "Unplugged", cost: 600),
    ]

    struct Tier {
        let name: String
        let min: Int
    }

    static let tiers: [Tier] = [
        Tier(name: "Bronza", min: 0),
        Tier(name: "Sidabras", min: 300),
        Tier(name: "Auksas", min: 1000),
    ]

    static func tier(for lifetime: Int) -> (current: Tier, next: Tier?) {
        let idx = tiers.lastIndex { lifetime >= $0.min } ?? 0
        return (tiers[idx], idx + 1 < tiers.count ? tiers[idx + 1] : nil)
    }
}
