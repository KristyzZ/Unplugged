import Foundation

/// Identifiable simulated credit. It is not a partner voucher or applied charge discount.
struct RewardRedemption: Codable, Equatable, Identifiable {
    let id: String // persistent idempotency key for one explicit redemption request
    let rewardId: String
    let titleKey: String
    let cost: Int
    let at: Date
    var title: String {
        Points.rewards.first { $0.id == rewardId }?.title
            ?? trKey(titleKey).replacingOccurrences(of: "%%", with: "%")
    }
}

extension Points.Reward {
    /// Store source keys rather than the language selected at redemption time.
    var titleKey: String {
        switch id {
        case "coffee": "Free coffee"
        case "kwh-5": "−5 %% on your next charge"
        case "eur-2": "€2 off charging"
        case "wash": "−50 %% car wash"
        case "kwh-20": "−20 %% on all charging for a week"
        default: title
        }
    }
}
