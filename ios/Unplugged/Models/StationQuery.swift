import Foundation

/// Filtering, sorting and map-pin selection for the Explore screen, as pure functions so they can
/// be tested and kept fast for about 2,000 stations.
enum StationQuery {
    struct Item: Identifiable, Equatable {
        let station: Station
        let distance: Double
        var id: String { station.id }
    }

    struct Filter {
        var onlyAvailable = false
        var fastOnly = false
        var myCarOnly = false
        var operatorId: String?
        var text = ""
    }

    /// Stations matching the filters, nearest to `origin` first.
    static func items(_ stations: [Station], origin: LatLng, vehicle: Vehicle, filter: Filter, now: Date = .now) -> [Item] {
        let query = filter.text.trimmingCharacters(in: .whitespaces).lowercased()
        let connectorFilter = ConnectorFilter(
            onlyAvailable: filter.onlyAvailable,
            minPowerKw: filter.fastOnly ? 50 : nil,
            vehicle: filter.myCarOnly ? vehicle : nil)
        return stations
            .filter { filter.operatorId == nil || $0.operatorId == filter.operatorId }
            .filter { $0.hasConnector(matching: connectorFilter, at: now) }
            .filter { query.isEmpty || "\($0.name) \($0.address) \($0.city)".lowercased().contains(query) }
            .map { Item(station: $0, distance: Geo.haversineKm(origin, $0.latLng)) }
            .sorted { $0.distance != $1.distance ? $0.distance < $1.distance : $0.id < $1.id }
    }

    struct Region: Equatable {
        var center: LatLng
        var latSpan: Double
        var lngSpan: Double

        func contains(_ p: LatLng, padding: Double = 0.15) -> Bool {
            abs(p.lat - center.lat) <= latSpan * (0.5 + padding) && abs(p.lng - center.lng) <= lngSpan * (0.5 + padding)
        }
    }

    /// The pins to draw. Only what is in the visible region (a little padded) gets one, and
    /// pins that would sit on top of each other are thinned: the screen is divided into a grid and
    /// each cell shows its most useful station (a free one first, then the most powerful), so
    /// zooming in reveals the rest. At most `limit` pins; the selected station always has one.
    static func pins(_ items: [Item], region: Region?, selectedId: String?, limit: Int = 150, thin: Bool = true,
                     now: Date = .now) -> (shown: [Item], truncated: Bool) {
        guard let region else { return (Array(items.prefix(limit)), items.count > limit) }
        var shown = items.filter { region.contains($0.station.latLng) }
        var truncated = false

        if thin, region.latSpan > 0, region.lngSpan > 0 {
            // About 9 pins across and 14 down a portrait phone screen.
            let latCell = region.latSpan / 14, lngCell = region.lngSpan / 9
            var best: [Int64: Item] = [:]
            for item in shown {
                let row = Int64(((item.station.lat - region.center.lat) / latCell).rounded(.down))
                let col = Int64(((item.station.lng - region.center.lng) / lngCell).rounded(.down))
                let key = row &* 100_003 &+ col
                if let current = best[key], rank(current.station, now: now) >= rank(item.station, now: now) { continue }
                best[key] = item
            }
            let kept = Set(best.values.map(\.id))
            truncated = kept.count < shown.count
            shown = shown.filter { kept.contains($0.id) }
        }

        if shown.count > limit {
            truncated = true
            shown = shown
                .sorted { Geo.haversineKm(region.center, $0.station.latLng) < Geo.haversineKm(region.center, $1.station.latLng) }
                .prefix(limit)
                .map { $0 }
        }
        if let selectedId, !shown.contains(where: { $0.id == selectedId }), let item = items.first(where: { $0.id == selectedId }) {
            shown.append(item)
        }
        return (shown, truncated)
    }

    /// Which station wins a crowded spot on the map: one with a free connector, then the faster one.
    private static func rank(_ station: Station, now: Date) -> Double {
        (station.freeCount(at: now) > 0 ? 1000 : 0) + station.maxPower
    }
}
