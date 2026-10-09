import Foundation

// Abuse reports: a car occupying a charging spot without charging.
// Evidence from several sources builds a confidence score; once it is high
// enough the report is confirmed and a sanction from the ladder applies.

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

    var category: ReportKind { kind ?? .wrongUsage }
    var confidence: Double { Reports.confidence(hasPhoto: hasPhoto, telemetryMatches: telemetryMatches, confirmations: confirmations) }
    var isConfirmed: Bool { confidence >= Reports.confirmThreshold }
}

enum Reports {
    static let confirmThreshold = 0.7

    static func confidence(hasPhoto: Bool, telemetryMatches: Bool, confirmations: Int) -> Double {
        var score = 0.1 // the report itself
        if hasPhoto { score += 0.3 }
        if telemetryMatches { score += 0.4 }
        score += Double(min(3, confirmations)) * 0.15
        return min(1, score)
    }

    /// Sanction for the n-th confirmed offence of the same plate.
    static func sanction(forOffence n: Int) -> String {
        switch n {
        case ...1: tr("Warning")
        case 2: tr("€20 fine")
        default: tr("Temporary account restriction (7 days)")
        }
    }

    /// Light normalisation for Lithuanian plates ("abc 123" → "ABC123").
    static func normalizePlate(_ plate: String) -> String {
        plate.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}
