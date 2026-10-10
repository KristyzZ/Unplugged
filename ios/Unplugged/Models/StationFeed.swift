import Foundation

// Real charging stations from the open Via Lietuva OCPI 2.3.0 feed (CC BY 4.0, no API key):
//   https://ev.vialietuva.lt/ocpi/2.3.0/locations and .../tariffs
// The same reduced shape (`FeedSnapshot`) comes from the live feed and from the bundled
// snapshot made by `python3 pipeline/run.py export-app`, and one builder turns it into `Station`s.
//
// Facts about the feed this code is written around (see pipeline/README.md):
// - `Link: rel="next"` is malformed, so pages are fetched by `offset`; `limit=1000` works.
// - `/tariffs` ignores paging and returns everything at once.
// - Some chargers appear twice with conflicting statuses; the freshest record wins.
// - `last_updated` is local Lithuanian time without a zone, is the time of the last *change* (not
//   of the last check) and is sometimes bogus (a charger "updated" in 2031).
// - `date_from` filters on the location's `last_updated`, which lags per-charger updates, so
//   incremental refresh would miss changes: we always reload everything.

// MARK: - Reduced feed shape (also the bundled snapshot's JSON)

struct FeedSnapshot: Codable, Equatable {
    var generatedAt: Date
    var source: String = "Via Lietuva OCPI"
    var stations: [FeedStation]
    var tariffs: [FeedTariff]
}

struct FeedStation: Codable, Hashable {
    var id: Int
    var party: String
    var name: String
    var address: String
    var city: String
    var lat: Double
    var lng: Double
    var evses: [FeedEvse]
}

struct FeedEvse: Codable, Hashable {
    /// The charger's id, e.g. "IBG-P-A9MY-A". Unique across the network.
    var id: String
    /// OCPI status: AVAILABLE, CHARGING, INOPERATIVE, OUTOFORDER, UNKNOWN, REMOVED, BLOCKED, ...
    var status: String
    /// `last_updated`: local time, no zone, last *change*.
    var updated: String?
    var connectors: [FeedConnector]
}

struct FeedConnector: Codable, Hashable {
    var id: Int
    var standard: String
    var watts: Int
    var tariff: String?
}

struct FeedTariff: Codable, Hashable {
    struct Component: Codable, Hashable {
        var type: String      // ENERGY, FLAT, TIME, PARKING_TIME
        var price: Double
        var step: Int?
    }
    struct Element: Codable, Hashable {
        /// Has time, date, duration or energy restrictions, so it is not the everyday price.
        var restricted: Bool
        var components: [Component]
    }
    var id: String
    var currency: String
    var elements: [Element]
}

// MARK: - What a connector costs

struct ConnectorTariff: Hashable {
    /// nil when the tariff has no usable energy price: shown as "price unknown", never guessed.
    var energyEurPerKwh: Double?
    /// One-off fee per session.
    var startEur: Double
    var perMinuteEur: Double
}

enum TariffResolver {
    /// The everyday price: unrestricted elements win; a tariff made only of restricted elements
    /// uses its first energy element. Non-euro tariffs and tariffs with no energy price give nil.
    static func resolve(_ tariff: FeedTariff) -> ConnectorTariff? {
        guard tariff.currency == "EUR" else { return nil }
        let unrestricted = tariff.elements.filter { !$0.restricted }
        func first(_ type: String, in elements: [FeedTariff.Element]) -> FeedTariff.Component? {
            elements.lazy.flatMap(\.components).first { $0.type == type }
        }
        let energy = first("ENERGY", in: unrestricted) ?? first("ENERGY", in: tariff.elements)
        guard let energy, energy.price.isFinite, energy.price >= 0 else { return nil }
        let start = first("FLAT", in: unrestricted)?.price ?? 0
        // OCPI TIME is a price per hour.
        let hourly = first("TIME", in: unrestricted)?.price ?? 0
        return ConnectorTariff(energyEurPerKwh: energy.price,
                               startEur: max(0, start),
                               perMinuteEur: max(0, hourly) / 60)
    }

    static func table(_ tariffs: [FeedTariff]) -> [String: ConnectorTariff] {
        var out: [String: ConnectorTariff] = [:]
        for t in tariffs { if let r = resolve(t) { out[t.id] = r } }
        return out
    }
}

// MARK: - Raw OCPI JSON -> reduced shape

enum OCPIDecoder {
    private struct Envelope<T: Decodable>: Decodable {
        let data: [Lossy<T>]
    }

    /// Decodes an element, or yields nil instead of failing the whole page when one record is malformed.
    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    private struct RawLocation: Decodable {
        struct Coordinates: Decodable { let latitude: String; let longitude: String }
        struct Evse: Decodable {
            struct Connector: Decodable {
                let id: Int
                let standard: String
                let max_electric_power: Int?
                let tariff_ids: [String]?
            }
            let evse_id: String
            let status: String?
            let last_updated: String?
            let connectors: [Lossy<Connector>]?
        }
        let id: Int
        let party_id: String
        let publish: Bool?
        let name: String?
        let address: String?
        let city: String?
        let coordinates: Coordinates
        let evses: [Lossy<Evse>]?
    }

    private struct RawTariff: Decodable {
        struct Element: Decodable {
            struct Component: Decodable {
                let type: String
                let price: String
                let step_size: Int?
            }
            let price_components: [Lossy<Component>]?
            /// Any value counts: we only need to know it is there.
            let restrictions: [String: JSONAny]?
        }
        let id: String
        let currency: String?
        let elements: [Lossy<Element>]?
    }

    private struct JSONAny: Decodable { init(from decoder: Decoder) throws {} }

    static func locations(from data: Data) throws -> [FeedStation] {
        let page = try JSONDecoder().decode(Envelope<RawLocation>.self, from: data)
        return page.data.compactMap(\.value).compactMap { loc in
            guard loc.publish ?? true,
                  let lat = Double(loc.coordinates.latitude), let lng = Double(loc.coordinates.longitude),
                  lat.isFinite, lng.isFinite, abs(lat) <= 90, abs(lng) <= 180, !(lat == 0 && lng == 0)
            else { return nil }
            let evses: [FeedEvse] = (loc.evses ?? []).compactMap(\.value).map { e in
                let connectors: [FeedConnector] = (e.connectors ?? []).compactMap(\.value).map {
                    FeedConnector(id: $0.id, standard: $0.standard, watts: $0.max_electric_power ?? 0, tariff: $0.tariff_ids?.first)
                }
                return FeedEvse(id: e.evse_id, status: e.status ?? "UNKNOWN", updated: e.last_updated, connectors: connectors)
            }
            return FeedStation(id: loc.id, party: loc.party_id, name: loc.name ?? "", address: loc.address ?? "",
                               city: loc.city ?? "", lat: lat, lng: lng, evses: evses)
        }
    }

    static func tariffs(from data: Data) throws -> [FeedTariff] {
        let page = try JSONDecoder().decode(Envelope<RawTariff>.self, from: data)
        return page.data.compactMap(\.value).map { raw in
            let elements: [FeedTariff.Element] = (raw.elements ?? []).compactMap(\.value).map { e in
                let components: [FeedTariff.Component] = (e.price_components ?? []).compactMap(\.value).compactMap {
                    guard let price = Double($0.price) else { return nil }
                    return FeedTariff.Component(type: $0.type, price: price, step: $0.step_size)
                }
                return FeedTariff.Element(restricted: !(e.restrictions ?? [:]).isEmpty, components: components)
            }
            return FeedTariff(id: raw.id, currency: raw.currency ?? "", elements: elements)
        }
    }
}

// MARK: - Reduced shape -> Station

enum StationBuilder {
    static let defaultSource = "Via Lietuva OCPI"

    /// A feed timestamp is local Lithuanian time without a zone.
    private static let vilnius: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vilnius")!
        return calendar
    }()

    /// Parses "2026-10-10T00:01:05" by hand: a DateFormatter per charger made loading the whole
    /// country many times slower.
    static func parseLocal(_ text: String?) -> Date? {
        guard let text else { return nil }
        let b = Array(text.utf8)
        guard b.count >= 19, b[4] == 45, b[7] == 45, b[10] == 84 || b[10] == 32, b[13] == 58, b[16] == 58 else { return nil }
        func n(_ i: Int, _ len: Int) -> Int? {
            var v = 0
            for k in i..<(i + len) {
                guard b[k] >= 48, b[k] <= 57 else { return nil }
                v = v * 10 + Int(b[k] - 48)
            }
            return v
        }
        guard let y = n(0, 4), let mo = n(5, 2), let d = n(8, 2), let h = n(11, 2), let mi = n(14, 2), let s = n(17, 2),
              (1...12).contains(mo), (1...31).contains(d), h < 24, mi < 60, s < 61 else { return nil }
        return vilnius.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))
    }

    /// When a charger really last changed, or nil when the feed's date is missing or impossible
    /// (it contains dates years in the future).
    static func changeDate(_ text: String?, now: Date) -> Date? {
        guard let date = parseLocal(text), date <= now.addingTimeInterval(24 * 3600) else { return nil }
        return date
    }

    /// One record per charger id: the one that changed most recently. A record with an impossible
    /// date ranks last. Stations left without chargers are dropped.
    static func dedupe(_ stations: [FeedStation], now: Date) -> [FeedStation] {
        // The winning record of each charger id: its station index, its position there and its rank.
        var best: [String: (station: Int, evse: Int, rank: Date)] = [:]
        for (si, s) in stations.enumerated() {
            for (ei, e) in s.evses.enumerated() {
                let rank = changeDate(e.updated, now: now) ?? .distantPast
                if let current = best[e.id], current.rank >= rank { continue }   // ties keep the earlier record
                best[e.id] = (si, ei, rank)
            }
        }
        return stations.enumerated().compactMap { si, s in
            var copy = s
            copy.evses = s.evses.enumerated().compactMap { ei, e in
                guard let winner = best[e.id], winner.station == si, winner.evse == ei else { return nil }
                return e
            }
            return copy.evses.isEmpty ? nil : copy
        }
    }

    static func status(_ ocpi: String) -> ConnectorStatus? {
        switch ocpi.uppercased() {
        case "AVAILABLE": .available
        case "CHARGING": .charging
        case "INOPERATIVE", "OUTOFORDER", "PLANNED": .offline
        case "BLOCKED": .blocked
        case "RESERVED": .reserved
        case "REMOVED": nil
        default: .unknown
        }
    }

    static func connectorType(_ standard: String) -> ConnectorType? {
        switch standard {
        case "IEC_62196_T2": .type2
        case "IEC_62196_T2_COMBO": .ccs2
        case "CHADEMO": .chademo
        default: nil
        }
    }

    /// "L3 | Inbalance grid" -> "L3".
    static func cleanName(_ raw: String, fallback: String) -> String {
        let head = raw.components(separatedBy: " | ").first ?? raw
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || looksLikeInternalId(trimmed) ? fallback : trimmed
    }

    /// Some operators use a system id as the station name ("PLTKAUJO60_EDLT-1"): no spaces, all
    /// capitals, digits and separators. The address is a better name.
    static func looksLikeInternalId(_ name: String) -> Bool {
        guard name.count >= 6, !name.contains(" ") else { return false }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.")
        return name.allSatisfy { allowed.contains($0) } && name.contains { $0.isNumber } && name.contains { "_-".contains($0) }
    }

    /// Stations for the app. `observedAt` is when this data was fetched (or the snapshot made):
    /// it is the status timestamp, **not** the feed's `last_updated`, which only says when a charger
    /// last changed. A charger that has been free for hours is still confirmed free right now.
    static func stations(from snapshot: FeedSnapshot, observedAt: Date? = nil, now: Date = .now) -> [Station] {
        let observed = observedAt ?? snapshot.generatedAt
        let tariffs = TariffResolver.table(snapshot.tariffs)
        let source = snapshot.source.isEmpty ? defaultSource : snapshot.source
        var usedConnectorIds = Set<String>()
        var out: [Station] = []
        out.reserveCapacity(snapshot.stations.count)

        for feed in dedupe(snapshot.stations, now: now) {
            var connectors: [Connector] = []
            for evse in feed.evses {
                guard let status = status(evse.status) else { continue }
                let changed = changeDate(evse.updated, now: now)
                for c in evse.connectors {
                    guard let type = connectorType(c.standard), c.watts > 0 else { continue }
                    let id = "ocpi-\(c.id)"
                    guard usedConnectorIds.insert(id).inserted else { continue }
                    connectors.append(Connector(
                        id: id, type: type, powerKw: Double(c.watts) / 1000, status: status,
                        provenance: Provenance(source: source, timestamp: observed, dataClass: .observed),
                        tariff: c.tariff.flatMap { tariffs[$0] },
                        changedAt: changed
                    ))
                }
            }
            guard !connectors.isEmpty else { continue }
            let headline = headlinePrice(connectors)
            out.append(Station(
                id: "ocpi-\(feed.id)",
                name: cleanName(feed.name, fallback: feed.address),
                address: feed.address,
                city: feed.city,
                lat: feed.lat, lng: feed.lng,
                operatorId: OperatorCatalog.operatorId(partyId: feed.party),
                pricePerKwh: headline ?? 0,
                connectors: connectors,
                // No busy-hour history exists yet (issue #37); empty means "no data", not "never busy".
                hourlyOccupancy: [],
                amenities: [],
                priceProvenance: headline == nil
                    ? .unspecified
                    : Provenance(source: source, timestamp: observed, dataClass: .observed),
                // Real data, simulated session: no real charger is started and no real payment is taken.
                capabilities: .demo(.fullCharging)
            ))
        }
        return out
    }

    /// The station's headline price: that of its fastest connector with a known price
    /// (lowest when tied), because that is the one most drivers choose.
    static func headlinePrice(_ connectors: [Connector]) -> Double? {
        connectors
            .compactMap { c in c.tariff?.energyEurPerKwh.map { (c.powerKw, $0) } }
            .sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
            .first?.1
    }
}

// MARK: - Where the data comes from

enum StationSource: String {
    /// Real stations from the open feed (default).
    case real
    /// The invented demo stations, kept for tests and the deterministic demo.
    case demo
}

/// What the Explore screen says about the data it is showing.
enum FeedStatus: Equatable {
    case demo
    case loading
    case live(at: Date)
    /// The last fetch failed; the data shown is from `dataFrom` (a previous fetch or the bundled snapshot).
    case offline(dataFrom: Date?)
}

extension FeedSnapshot {
    /// The snapshot bundled with the app (`Data/stations.json`, made by `pipeline/run.py export-app`).
    static func bundled(in bundle: Bundle = .main) -> FeedSnapshot? {
        guard let url = bundle.url(forResource: "stations", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> FeedSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(FeedSnapshot.self, from: data)
    }
}

// MARK: - Fetching

protocol HTTPFetching {
    func get(_ url: URL) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPFetching {
    func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (body, response) = try await self.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return (body, http)
    }
}

protocol StationFeeding {
    func fetch() async throws -> FeedSnapshot
}

struct OCPIStationFeed: StationFeeding {
    /// The open feed. For testing, `-unplugged.feedBase <url>` on the launch arguments points the app
    /// elsewhere (an unreachable address behaves exactly like being offline).
    static var base: URL {
        UserDefaults.standard.string(forKey: "unplugged.feedBase").flatMap(URL.init(string:))
            ?? URL(string: "https://ev.vialietuva.lt/ocpi/2.3.0")!
    }
    static let pageSize = 1000
    /// Safety net against a feed that never ends.
    static let maxPages = 12

    var http: HTTPFetching
    var now: () -> Date = { Date() }

    init(http: HTTPFetching? = nil, now: @escaping () -> Date = { Date() }) {
        if let http {
            self.http = http
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.http = URLSession(configuration: configuration)
        }
        self.now = now
    }

    private func locationsURL(offset: Int) -> URL {
        var c = URLComponents(url: Self.base.appendingPathComponent("locations"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "limit", value: String(Self.pageSize)), URLQueryItem(name: "offset", value: String(offset))]
        return c.url!
    }

    private func page(offset: Int) async throws -> (stations: [FeedStation], total: Int?) {
        var lastError: Error = URLError(.unknown)
        for _ in 0..<2 {                      // one retry
            do {
                let (data, response) = try await http.get(locationsURL(offset: offset))
                let total = response.value(forHTTPHeaderField: "X-Total-Count").flatMap { Int($0) }
                return (try OCPIDecoder.locations(from: data), total)
            } catch { lastError = error }
        }
        throw lastError
    }

    func fetch() async throws -> FeedSnapshot {
        // The first page tells us the total; the rest are fetched together. Any failed page fails
        // the whole refresh: a half-loaded map would be worse than the previous complete one.
        let first = try await page(offset: 0)
        var stations = first.stations
        if let total = first.total, total > Self.pageSize {
            let offsets = Array(stride(from: Self.pageSize, to: min(total, Self.pageSize * Self.maxPages), by: Self.pageSize))
            let rest = try await withThrowingTaskGroup(of: (Int, [FeedStation]).self) { group in
                for offset in offsets { group.addTask { (offset, try await page(offset: offset).stations) } }
                var pages: [(Int, [FeedStation])] = []
                for try await p in group { pages.append(p) }
                return pages.sorted { $0.0 < $1.0 }
            }
            stations += rest.flatMap(\.1)
        } else if first.total == nil {
            // No count header: keep going until a page comes back empty.
            var offset = Self.pageSize
            while offset < Self.pageSize * Self.maxPages {
                let next = try await page(offset: offset)
                if next.stations.isEmpty { break }
                stations += next.stations
                offset += Self.pageSize
            }
        }

        // /tariffs ignores paging and returns everything in one response.
        let tariffs = (try? await http.get(Self.base.appendingPathComponent("tariffs")))
            .flatMap { try? OCPIDecoder.tariffs(from: $0.0) } ?? []
        return FeedSnapshot(generatedAt: now(), source: StationBuilder.defaultSource, stations: stations, tariffs: tariffs)
    }
}
