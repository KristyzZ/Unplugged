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

    /// The pins to draw: only what is in the visible region (a little padded), at most `limit`
    /// closest to the middle of the screen, plus the selected station. Drawing every station of
    /// the country would make the map stutter.
    static func pins(_ items: [Item], region: Region?, selectedId: String?, limit: Int = 150) -> (shown: [Item], truncated: Bool) {
        guard let region else { return (Array(items.prefix(limit)), items.count > limit) }
        let inside = items.filter { region.contains($0.station.latLng) }
        var shown = inside
        let truncated = inside.count > limit
        if truncated {
            shown = inside
                .sorted { Geo.haversineKm(region.center, $0.station.latLng) < Geo.haversineKm(region.center, $1.station.latLng) }
                .prefix(limit)
                .map { $0 }
        }
        if let selectedId, !shown.contains(where: { $0.id == selectedId }), let item = items.first(where: { $0.id == selectedId }) {
            shown.append(item)
        }
        return (shown, truncated)
    }
}
