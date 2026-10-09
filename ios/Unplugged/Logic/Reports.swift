import Foundation

// Abuse reports: a car occupying a charging spot without charging.
// Evidence from several sources builds a confidence score; once it is high
// enough the report is confirmed and a sanction from the ladder applies.
//
// The strongest evidence is the charger itself: if its spot sensor says
// "occupied" while no session is running, the report confirms at once. A
// photo whose plate the phone could read counts more than a plain photo.

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
    /// The plate was read from the photo on the phone (and matches the one entered).
    var plateFromPhoto: Bool? = nil
    var evidence: StationEvidence? = nil

    var category: ReportKind { kind ?? .wrongUsage }
    /// Older reports only stored whether the station data matched.
    var stationEvidence: StationEvidence { evidence ?? (telemetryMatches ? .occupiedNoSession : .unknown) }
    var confidence: Double {
        Reports.confidence(hasPhoto: hasPhoto, plateFromPhoto: plateFromPhoto ?? false,
                           evidence: stationEvidence, confirmations: confirmations)
    }
    var isConfirmed: Bool { confidence >= Reports.confirmThreshold }
}

/// What the charger's own data says about "a car is blocking this spot".
enum StationEvidence: String, Codable {
    /// Spot sensor: occupied, but no charging session. The case we look for.
    case occupiedNoSession
    /// No session on that charger: consistent with a car that isn't charging.
    case noSession
    /// Finished charging and still parked: the idle fee already applies.
    case finishedParked
    /// A session is running there: the car in the spot is charging.
    case charging
    /// Charger offline or spot not known.
    case unknown

    init(_ status: ConnectorStatus) {
        switch status {
        case .blocked: self = .occupiedNoSession
        case .available, .reserved: self = .noSession
        case .idle: self = .finishedParked
        case .charging: self = .charging
        case .offline: self = .unknown
        }
    }

    /// For "not sure which spot": the strongest sign at the station.
    init(station: Station) {
        let statuses = station.connectors.map(\.status)
        if statuses.contains(.blocked) { self = .occupiedNoSession }
        else if statuses.contains(.idle) { self = .finishedParked }
        else if statuses.contains(.available) { self = .noSession }
        else if statuses.contains(.charging) { self = .charging }
        else { self = .unknown }
    }

    var weight: Double {
        switch self {
        case .occupiedNoSession: 0.6
        case .finishedParked: 0.3
        case .noSession: 0.25
        case .charging: -0.3
        case .unknown: 0
        }
    }

    var supports: Bool { weight > 0 }
    var contradicts: Bool { weight < 0 }

    var detail: String {
        switch self {
        case .occupiedNoSession: tr("Spot sensor: occupied, no charging session")
        case .noSession: tr("Charger: no charging session")
        case .finishedParked: tr("Charger: finished charging, car still parked")
        case .charging: tr("Charger: a car is charging there")
        case .unknown: tr("Charger: no data")
        }
    }
}

enum Reports {
    static let confirmThreshold = 0.7

    static let confirmationWeight = 0.15

    static func confidence(hasPhoto: Bool, plateFromPhoto: Bool, evidence: StationEvidence, confirmations: Int) -> Double {
        var score = 0.1 // the report itself
        if hasPhoto { score += 0.2 }
        if hasPhoto && plateFromPhoto { score += 0.2 }
        score += evidence.weight
        score += Double(min(3, confirmations)) * confirmationWeight
        return min(1, max(0, score))
    }

    /// Other drivers still needed to confirm (0 = confirmed now; nil = even three won't do).
    static func confirmationsNeeded(hasPhoto: Bool, plateFromPhoto: Bool, evidence: StationEvidence) -> Int? {
        for n in 0...3 where confidence(hasPhoto: hasPhoto, plateFromPhoto: plateFromPhoto, evidence: evidence, confirmations: n) >= confirmThreshold - 1e-9 {
            return n
        }
        return nil
    }

    /// Sanction for the n-th confirmed offence of the same plate.
    static func sanction(forOffence n: Int) -> String {
        switch n {
        case ...1: tr("Warning")
        case 2: tr("€20 fine")
        default: tr("Temporary account restriction (7 days)")
        }
    }

    /// "abc123" → "ABC 123" for the Lithuanian format; others just upper-cased.
    static func formatPlate(_ plate: String) -> String {
        let compact = normalizePlate(plate)
        if let match = PlateReader.match(compact), match.lithuanian { return match.plate }
        return plate.uppercased().trimmingCharacters(in: .whitespaces)
    }

    /// Light normalisation for Lithuanian plates ("abc 123" → "ABC123").
    static func normalizePlate(_ plate: String) -> String {
        plate.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}
