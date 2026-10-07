import Foundation

enum AvailabilityLevel {
    case free, limited, full, offline
}

extension Station {
    func count(_ status: ConnectorStatus) -> Int {
        connectors.filter { $0.status == status }.count
    }

    var freeCount: Int { count(.available) }

    var workingCount: Int { connectors.filter { $0.status != .offline }.count }

    var maxPower: Double { connectors.map(\.powerKw).max() ?? 0 }

    var availability: AvailabilityLevel {
        let working = workingCount
        if working == 0 { return .offline }
        let free = freeCount
        if free == 0 { return .full }
        if Double(free) / Double(working) < 0.34 { return .limited }
        return .free
    }

    /// Probability that at least one connector is usually free at a given hour,
    /// from historical occupancy. Treats connectors as independent: 1 - pⁿ.
    func probabilityFree(atHour hour: Int) -> Double {
        let p = hourlyOccupancy[((hour % 24) + 24) % 24]
        let n = max(1, workingCount)
        return 1 - pow(p, Double(n))
    }

    /// Current demand (0–1): live occupancy blended with the historical norm.
    func demandLevel(hour: Int) -> Double {
        let working = workingCount
        let live = working == 0 ? 1 : 1 - Double(freeCount) / Double(working)
        let hist = hourlyOccupancy[hour % 24]
        return min(1, 0.7 * live + 0.3 * hist)
    }

    /// Hours (0–23) where the station is usually busiest.
    func peakHours(top: Int = 3) -> [Int] {
        hourlyOccupancy.enumerated()
            .sorted { $0.element > $1.element }
            .prefix(top)
            .map(\.offset)
            .sorted()
    }

    /// Least busy hour within the next `window` hours.
    func bestHour(from hour: Int, window: Int = 6) -> Int {
        var best = hour
        for i in 0...window {
            let h = (hour + i) % 24
            if hourlyOccupancy[h] < hourlyOccupancy[best] { best = h }
        }
        return best
    }
}
