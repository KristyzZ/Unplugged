import Foundation

// Abuse reports: a car occupying a charging spot without charging.
// Evidence from several sources builds a confidence score; once it is high
// enough the report is confirmed and a sanction from the ladder applies.

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
        case ...1: "Įspėjimas"
        case 2: "Bauda 20 €"
        default: "Laikinas paskyros apribojimas (7 d.)"
        }
    }

    /// Light normalisation for Lithuanian plates ("abc 123" → "ABC123").
    static func normalizePlate(_ plate: String) -> String {
        plate.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}
