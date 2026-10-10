import Foundation

// Operator / city analytics derived from (demo) session history.

struct StationStats: Identifiable {
    var id: String { station.id }
    let station: Station
    let sessionsPerDay: Int
    let avgChargeMin: Int
    let avgIdleMin: Int
    /// Share of occupied time where the car was not charging.
    let idleShare: Double
    let utilization: Double
    let abuseCases7d: Int
}

struct NetworkSummary {
    let stations: [StationStats]
    let sessionsPerDay: Int
    let avgIdleMin: Double
    let avgIdleMinAfter: Double
    let idleHoursPerDay: Double
    let idleHoursSavedPerDay: Double
    let extraSessionsPerDay: Int
    let abuseCases7d: Int
    let hourlyDemand: [Double]
}

enum Analytics {
    /// Assumed effect of grace period + idle fee + rewards on idle time.
    static let defaultIdleReduction = 0.7

    static func stats(_ station: Station) -> StationStats {
        var r = SeededRandom("stats:\(station.id)")
        let fast = station.connectors.contains { $0.powerKw >= 50 }
        let utilization = station.hourlyOccupancy.reduce(0, +) / 24
        let avgCharge = Int((fast ? 28 + r.next() * 20 : 110 + r.next() * 80).rounded())
        let avgIdle = Int((fast ? 8 + r.next() * 14 : 25 + r.next() * 55).rounded())
        let occupiedMinPerDay = utilization * 24 * 60 * Double(station.connectors.count)
        let sessions = Int((occupiedMinPerDay / Double(avgCharge + avgIdle)).rounded())
        return StationStats(
            station: station,
            sessionsPerDay: sessions,
            avgChargeMin: avgCharge,
            avgIdleMin: avgIdle,
            idleShare: Double(avgIdle) / Double(avgCharge + avgIdle),
            utilization: utilization,
            abuseCases7d: Int((r.next() * (station.city == "Vilnius" ? 9 : 4)).rounded())
        )
    }

    static func summary(_ stations: [Station], idleReduction: Double = defaultIdleReduction) -> NetworkSummary {
        let all = stations.map(stats)
        let sessions = all.reduce(0) { $0 + $1.sessionsPerDay }
        let idleTotal = all.reduce(0.0) { $0 + Double($1.sessionsPerDay * $1.avgIdleMin) }
        let chargeTotal = all.reduce(0.0) { $0 + Double($1.sessionsPerDay * $1.avgChargeMin) }
        let avgIdle = idleTotal / Double(max(1, sessions))
        let avgCharge = chargeTotal / Double(max(1, sessions))
        let saved = idleTotal * idleReduction
        let hourly = (0..<24).map { h in
            stations.reduce(0.0) { $0 + ($1.occupancy(atHour: h) ?? 0) } / Double(max(1, stations.count))
        }
        return NetworkSummary(
            stations: all,
            sessionsPerDay: sessions,
            avgIdleMin: avgIdle,
            avgIdleMinAfter: avgIdle * (1 - idleReduction),
            idleHoursPerDay: idleTotal / 60,
            idleHoursSavedPerDay: saved / 60,
            // Freed bay-time divided by a typical session (charge + reduced idle).
            extraSessionsPerDay: Int((saved / max(1, avgCharge + avgIdle * (1 - idleReduction))).rounded()),
            abuseCases7d: all.reduce(0) { $0 + $1.abuseCases7d },
            hourlyDemand: hourly
        )
    }
}
