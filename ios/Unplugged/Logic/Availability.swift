import Foundation

enum AvailabilityLevel {
    case free, limited, full, offline
    /// We cannot say: statuses are missing or stale. Never shown as available.
    case unknown
}

// MARK: - Connector status with freshness

extension Connector {
    /// The status we can stand behind at `now`: a stale status becomes `.unknown`.
    func effectiveStatus(at now: Date = .now, maxAge: TimeInterval = Freshness.statusMaxAge) -> ConnectorStatus {
        provenance.isStale(at: now, maxAge: maxAge) ? .unknown : status
    }

    /// True only for a fresh `available` status that is a fact (demo or observed), not a prediction.
    func isConfirmedAvailable(at now: Date = .now, maxAge: TimeInterval = Freshness.statusMaxAge) -> Bool {
        effectiveStatus(at: now, maxAge: maxAge) == .available && provenance.dataClass != .predicted
    }
}

/// Station-level filter that must be satisfied by **one** connector. Checking "available", "fast" and
/// "fits my car" separately at station level could be satisfied by three different connectors, so a
/// station with a busy fast connector and a free slow one would wrongly pass "available and fast".
struct ConnectorFilter {
    var onlyAvailable = false
    var minPowerKw: Double?
    var vehicle: Vehicle?
}

extension Station {
    // MARK: Current connector states (freshness-aware)

    func effectiveStatuses(at now: Date = .now) -> [ConnectorStatus] {
        connectors.map { $0.effectiveStatus(at: now) }
    }

    func count(_ status: ConnectorStatus, at now: Date = .now) -> Int {
        effectiveStatuses(at: now).filter { $0 == status }.count
    }

    /// Connectors that are confirmed available right now. Unknown and stale never count.
    func freeCount(at now: Date) -> Int {
        connectors.filter { $0.isConfirmedAvailable(at: now) }.count
    }

    var freeCount: Int { freeCount(at: .now) }

    /// Connectors not known to be out of service. Unknown ones are included (they may work), but
    /// they are never counted as free.
    func workingCount(at now: Date) -> Int {
        effectiveStatuses(at: now).filter { $0 != .offline }.count
    }

    var workingCount: Int { workingCount(at: .now) }

    func unknownCount(at now: Date = .now) -> Int { count(.unknown, at: now) }

    var maxPower: Double { connectors.map(\.powerKw).max() ?? 0 }

    func availability(at now: Date) -> AvailabilityLevel {
        let statuses = effectiveStatuses(at: now)
        guard !statuses.isEmpty else { return .offline }
        guard statuses.contains(where: { $0 != .unknown }) else { return .unknown }
        let working = statuses.filter { $0 != .offline }.count
        guard working > 0 else { return .offline }
        let free = freeCount(at: now)
        if free == 0 {
            // Some connectors may be free but we cannot tell: do not claim the station is full.
            return statuses.contains(.unknown) ? .unknown : .full
        }
        return Double(free) / Double(working) < 0.34 ? .limited : .free
    }

    var availability: AvailabilityLevel { availability(at: .now) }

    /// Does one connector satisfy every active filter?
    func hasConnector(matching filter: ConnectorFilter, at now: Date = .now) -> Bool {
        connectors.contains { c in
            (!filter.onlyAvailable || c.isConfirmedAvailable(at: now))
                && (filter.minPowerKw.map { c.powerKw >= $0 } ?? true)
                && (filter.vehicle.map { Charging.isCompatible($0, c) } ?? true)
        }
    }

    // MARK: Historical occupancy (validated)

    /// 24 finite values in 0...1, one per hour. Anything else is not trusted.
    var hasValidOccupancyHistory: Bool {
        hourlyOccupancy.count == 24 && hourlyOccupancy.allSatisfy { $0.isFinite && (0...1).contains($0) }
    }

    /// Typical occupancy (0-1) at `hour` (any integer; wraps around 24), or nil without valid history.
    func occupancy(atHour hour: Int) -> Double? {
        guard hasValidOccupancyHistory else { return nil }
        return hourlyOccupancy[((hour % 24) + 24) % 24]
    }

    /// Probability that at least one connector is usually free at a given hour, from historical
    /// occupancy. Treats connectors as independent: 1 - p^n. A station with no working connector has
    /// probability 0; nil means there is no usable history (not "no chance").
    func probabilityFree(atHour hour: Int, at now: Date = .now) -> Double? {
        guard let p = occupancy(atHour: hour) else { return nil }
        return 1 - pow(p, Double(workingCount(at: now)))
    }

    /// Current demand (0-1): live occupancy blended with the historical norm. Without valid
    /// history it is the live occupancy alone.
    func demandLevel(hour: Int, at now: Date = .now) -> Double {
        let working = workingCount(at: now)
        let live = working == 0 ? 1 : 1 - Double(freeCount(at: now)) / Double(working)
        guard let hist = occupancy(atHour: hour) else { return min(1, max(0, live)) }
        return min(1, 0.7 * live + 0.3 * hist)
    }

    /// Hours (0-23) where the station is usually busiest. Empty without valid history.
    func peakHours(top: Int = 3) -> [Int] {
        guard hasValidOccupancyHistory else { return [] }
        return hourlyOccupancy.enumerated()
            .sorted { $0.element > $1.element }
            .prefix(top)
            .map(\.offset)
            .sorted()
    }

    /// Least busy hour within the next `window` hours. Without valid history, the starting hour.
    func bestHour(from hour: Int, window: Int = 6) -> Int {
        let start = ((hour % 24) + 24) % 24
        guard hasValidOccupancyHistory else { return start }
        var best = start
        for i in 0...max(0, window) {
            let h = (start + i) % 24
            if hourlyOccupancy[h] < hourlyOccupancy[best] { best = h }
        }
        return best
    }
}
