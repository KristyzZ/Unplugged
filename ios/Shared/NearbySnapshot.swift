import Foundation

/// What the home-screen widget shows: the nearest fast chargers with a free
/// spot that fit your car. The app writes it to the shared App Group whenever
/// station data refreshes; the widget only reads it (it has no network or
/// station data of its own).
struct NearbySnapshot: Codable, Equatable {
    struct Charger: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let address: String
        let freeCount: Int
        let workingCount: Int
        let maxKw: Double
        let pricePerKwh: Double
        let distanceKm: Double
    }

    let generatedAt: Date
    /// Nearest first. Only stations with a free fast connector for your car;
    /// when none has one, the nearest fast ones (full) so the widget isn't empty.
    let chargers: [Charger]
    let anyFree: Bool
    let carName: String
    /// "en" or "lt".
    let lang: String

    static let appGroup = "group.lt.vilniushack.unplugged"
    static let widgetKind = "NearbyCharger"
    private static let key = "nearby.snapshot.v1"

    /// Nil without the App Group (device builds without a paid team).
    private static var store: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load() -> NearbySnapshot? {
        guard let data = store?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(NearbySnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.store?.set(data, forKey: Self.key)
    }

    /// Deep link into the app (handled in RootView).
    static func url(station id: String) -> URL { URL(string: "unplugged://station/\(id)")! }
    static let chargingURL = URL(string: "unplugged://charging")!
}
