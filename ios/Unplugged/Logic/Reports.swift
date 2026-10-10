import Foundation

// Abuse reports: a car occupying a charging spot without charging.
// Confidence is a demo signal, separate from explicit simulated review.
// No real operator moderation, fines or account restrictions are performed.

enum ReportKind: String, Codable, CaseIterable, Identifiable {
    case wrongUsage, chargerProblem, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wrongUsage: tr("Wrong use of the charger")
        case .chargerProblem: tr("Charger problem")
        case .other: tr("Other")
        }
    }

    var placeholder: String {
        switch self {
        case .wrongUsage: tr("E.g., a petrol car is parked in the charging spot")
        case .chargerProblem: tr("E.g., the connector won't lock or the screen is dead")
        case .other: tr("Describe what's wrong")
        }
    }

    var photoHint: String {
        switch self {
        case .wrongUsage: tr("A photo with a visible plate greatly increases credibility.")
        case .chargerProblem, .other: tr("A photo helps the operator understand the problem.")
        }
    }
}

enum ReportReviewState: String, Codable, CaseIterable {
    case submitted, pendingReview, reviewedAccepted, reviewedRejected
    var isReviewed: Bool { self == .reviewedAccepted || self == .reviewedRejected }
    var title: String {
        switch self {
        case .submitted: tr("Submitted locally")
        case .pendingReview: tr("Pending demo review")
        case .reviewedAccepted: tr("Demo review: accepted")
        case .reviewedRejected: tr("Demo review: rejected")
        }
    }
}

struct AbuseReport: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    let stationId: String
    let plate: String
    let description: String
    let hasPhoto: Bool
    /// Station telemetry says the bay is occupied but no session is running.
    let telemetryMatches: Bool
    var confirmations: Int
    let createdAt: Date
    let byMe: Bool
    // Added later; optional so older saved reports still decode (they are wrong-use reports).
    var kind: ReportKind? = nil
    var connectorId: String? = nil
    var reviewState: ReportReviewState? = nil
    var confirmedByMe: Bool? = nil
    var reportRewardGranted: Bool? = nil
    var reviewedAt: Date? = nil
    var reviewStatus: ReportReviewState { reviewState ?? .pendingReview }
    var canConfirm: Bool { !byMe && confirmedByMe != true && !reviewStatus.isReviewed }

    var category: ReportKind { kind ?? .wrongUsage }
    var confidence: Double { Reports.confidence(hasPhoto: hasPhoto, telemetryMatches: telemetryMatches, confirmations: confirmations) }
    var isConfirmed: Bool { reviewStatus == .reviewedAccepted }
}

enum Reports {
    static let confirmThreshold = 0.7

    static func confidence(hasPhoto: Bool, telemetryMatches: Bool, confirmations: Int) -> Double {
        var score = 0.1 // the report itself
        if hasPhoto { score += 0.3 }
        if telemetryMatches { score += 0.4 }
        score += Double(max(0, min(3, confirmations))) * 0.15
        return min(1, score)
    }

    /// Sanction for the n-th confirmed offence of the same plate.
    static func sanction(forOffence n: Int) -> String {
        switch n {
        case ...1: tr("Demo warning (not applied)")
        case 2: tr("Demo €20 fine (not applied)")
        default: tr("Demo account restriction for 7 days (not applied)")
        }
    }

    /// Light normalisation for Lithuanian plates ("abc 123" → "ABC123").
    static func normalizePlate(_ plate: String) -> String {
        plate.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}
