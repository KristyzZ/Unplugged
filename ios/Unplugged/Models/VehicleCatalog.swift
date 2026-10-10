import Foundation

/// The bundled list of electric car models (Data/vehicles.json, made by
/// `python3 pipeline/run.py vehicles` from Open EV Data). Loaded once, on
/// first use.
enum VehicleCatalog {
    /// Required by the data licence; shown on the car pages.
    static let attribution = "Open EV Data (github.com/KilowattApp/open-ev-data)"

    private struct File: Decodable {
        let sourceUpdatedAt: String?
        let aliases: [String: String]
        let vehicles: [Vehicle]
    }

    private static let file: File = {
        guard let url = Bundle.main.url(forResource: "vehicles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data),
              !file.vehicles.isEmpty
        else {
            assertionFailure("vehicles.json missing or unreadable")
            return File(sourceUpdatedAt: nil, aliases: [:], vehicles: [fallback])
        }
        return file
    }()

    private static let byId: [String: Vehicle] = Dictionary(file.vehicles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    /// Sorted by brand, model, variant, newest first.
    static var all: [Vehicle] { file.vehicles }

    /// When the source data was last updated (yyyy-mm-dd).
    static var sourceDate: String? { file.sourceUpdatedAt.map { String($0.prefix(10)) } }

    /// The default car for new users.
    static let defaultId = "ioniq5"

    /// A car by id; also accepts the app's earlier built-in ids ("ioniq5", …).
    static func vehicle(_ id: String) -> Vehicle {
        byId[id] ?? file.aliases[id].flatMap { byId[$0] } ?? byId[file.aliases[defaultId] ?? ""] ?? file.vehicles[0]
    }

    /// Brands with how many models each has, alphabetical.
    static let brands: [(name: String, count: Int)] = {
        var counts: [String: Int] = [:]
        for v in file.vehicles { counts[v.brand, default: 0] += 1 }
        return counts.map { ($0.key, $0.value) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    static func vehicles(brand: String) -> [Vehicle] {
        file.vehicles.filter { $0.brand == brand }
    }

    /// Every word must match somewhere in brand, model, variant or year.
    static func search(_ query: String, limit: Int = 80) -> [Vehicle] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        var results: [Vehicle] = []
        for v in file.vehicles {
            let haystack = "\(v.brand) \(v.model) \(v.variant) \(v.year.map(String.init) ?? "")".lowercased()
            if words.allSatisfy({ haystack.contains($0) }) {
                results.append(v)
                if results.count == limit { break }
            }
        }
        return results
    }

    /// Only used if the bundled file can't be read.
    private static let fallback = Vehicle(
        id: "ioniq5", brand: "Hyundai", model: "IONIQ 5", variant: "Long Range 2WD", year: 2021,
        batteryKwh: 74, consumptionKwhPer100: 18.5, acKw: 11, acPhases: 3, dcKw: 233,
        connectors: [.ccs2, .type2], curve: nil, curveMeasured: nil
    )
}
