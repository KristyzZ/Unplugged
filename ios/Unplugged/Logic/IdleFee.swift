import Foundation

/// Idle-fee rules: after charging ends the driver gets a grace period, then a
/// progressively growing per-minute fee. All values are tunable policy knobs.
enum IdleFee {
    static let graceMin = 5
    static let graceMax = 15

    /// Dynamic grace period. Low demand → 15 min, high demand → 5 min.
    static func graceMinutes(demand: Double) -> Int {
        let d = min(1, max(0, demand))
        if d <= 0.4 { return graceMax }
        if d >= 0.9 { return graceMin }
        let t = (d - 0.4) / 0.5
        return Int((Double(graceMax) - t * Double(graceMax - graceMin)).rounded())
    }

    struct Tier: Hashable {
        /// Tier starts this many minutes after the grace period ends.
        let fromMin: Double
        let eurPerMin: Double
    }

    static let tiers: [Tier] = [
        Tier(fromMin: 0, eurPerMin: 0.10),
        Tier(fromMin: 10, eurPerMin: 0.25),
        Tier(fromMin: 30, eurPerMin: 0.50),
    ]

    static let capEur = 40.0

    /// Total idle fee for `minutes` spent idle after the grace period ended.
    static func fee(minutes: Double) -> Double {
        guard minutes > 0 else { return 0 }
        var total = 0.0
        for (i, tier) in tiers.enumerated() {
            let end = i + 1 < tiers.count ? tiers[i + 1].fromMin : .infinity
            if minutes <= tier.fromMin { break }
            total += (min(minutes, end) - tier.fromMin) * tier.eurPerMin
        }
        return min(capEur, (total * 100).rounded() / 100)
    }

    static func currentRate(minutes: Double) -> Double {
        tiers.last { minutes >= $0.fromMin }?.eurPerMin ?? 0
    }
}
