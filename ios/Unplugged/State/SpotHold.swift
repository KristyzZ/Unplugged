import Foundation

/// A charger kept free for a driver from the virtual queue. When someone
/// moves their car while others are waiting, the spot isn't up for grabs:
/// it's held for the next driver in line for a few minutes.
struct SpotHold: Codable, Equatable, Identifiable {
    static let minutes: Double = 10

    let stationId: String
    let stationName: String
    let connectorId: String
    let connectorLabel: String
    /// Simulated-clock times (demo speed-up aware).
    let startedAt: Date
    var until: Date
    /// Held for you (you were next in line), or for the next driver after you left.
    let forMe: Bool
    /// Optional additions keep the original persisted handover holds readable.
    var bookedAt: Date? = nil
    var releasedAt: Date? = nil
    var readyAnnounced: Bool? = nil

    var id: String { "\(stationId)|\(connectorId)" }

    var duration: TimeInterval { until.timeIntervalSince(startedAt) }

    func isActive(at now: Date) -> Bool {
        releasedAt == nil && startedAt <= now && now < until
    }
}
