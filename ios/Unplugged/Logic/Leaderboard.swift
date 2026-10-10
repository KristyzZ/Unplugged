import Foundation

/// Community ranking by lifetime points or by CO₂ saved by driving electric.
/// There is no backend yet, so the other drivers are demo data; "you" is real.
enum Leaderboard {
    enum Metric: String, CaseIterable, Identifiable {
        case points, co2
        var id: String { rawValue }
    }

    struct Driver: Equatable, Identifiable {
        let id: String
        let name: String
        let points: Int
        let co2Kg: Double
        var isYou = false

        func value(_ metric: Metric) -> Double {
            metric == .points ? Double(points) : co2Kg
        }
    }

    struct Row: Equatable, Identifiable {
        let rank: Int
        let driver: Driver
        var id: String { driver.id }
    }

    /// kg CO₂ avoided per kWh charged: a petrol car at 6.5 l/100 km emits
    /// ~15 kg per 100 km; an EV uses ~17 kWh per 100 km on a grid emitting
    /// ~0.1 kg per kWh. (15 / 17) − 0.1 ≈ 0.78. An estimate, not a measurement.
    static let co2KgPerKwh = 0.78

    static func energyKwh(_ s: ChargingSession) -> Double {
        max(0, s.targetSoc - s.startSoc) / 100 * s.batteryKwh
    }

    static func co2Saved(_ sessions: [ChargingSession]) -> Double {
        sessions.reduce(0) { $0 + energyKwh($1) } * co2KgPerKwh
    }

    /// Ranked best first. Ties share a rank; on a tie you are listed first.
    static func ranked(_ drivers: [Driver], by metric: Metric) -> [Row] {
        let sorted = drivers.sorted {
            let a = $0.value(metric), b = $1.value(metric)
            return a != b ? a > b : ($0.isYou && !$1.isYou)
        }
        var rows: [Row] = []
        for (i, d) in sorted.enumerated() {
            let rank = i > 0 && sorted[i - 1].value(metric) == d.value(metric) ? rows[i - 1].rank : i + 1
            rows.append(Row(rank: rank, driver: d))
        }
        return rows
    }

    /// The compact view: the top `limit` rows, plus your row if you are below them.
    static func compact(_ rows: [Row], limit: Int = 3) -> (top: [Row], you: Row?) {
        let top = Array(rows.prefix(limit))
        let you = top.contains { $0.driver.isYou } ? nil : rows.first { $0.driver.isYou }
        return (top, you)
    }

    static let demoDrivers: [Driver] = [
        Driver(id: "d1", name: "Rūta K.", points: 1_240, co2Kg: 612),
        Driver(id: "d2", name: "Tomas V.", points: 980, co2Kg: 701),
        Driver(id: "d3", name: "Eglė M.", points: 860, co2Kg: 455),
        Driver(id: "d4", name: "Mantas P.", points: 610, co2Kg: 388),
        Driver(id: "d5", name: "Ieva S.", points: 420, co2Kg: 290),
        Driver(id: "d6", name: "Lukas B.", points: 315, co2Kg: 174),
        Driver(id: "d7", name: "Greta J.", points: 190, co2Kg: 96),
        Driver(id: "d8", name: "Paulius D.", points: 85, co2Kg: 41),
    ]
}
