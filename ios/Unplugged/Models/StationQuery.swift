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
        /// Only chargers that private hosts share.
        var privateOnly = false
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
            .filter { !filter.privateOnly || $0.operatorId == HostListing.operatorId }
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

    // MARK: Clusters

    /// A map marker: one station, or several close together shown as a count.
    struct Cluster: Identifiable, Equatable {
        let items: [Item]
        let center: LatLng
        /// Stable while the same stations are grouped, so markers don't flicker.
        var id: String { items.count == 1 ? items[0].id : "c:" + items.map(\.id).sorted().joined(separator: ",") }
        var single: Item? { items.count == 1 ? items[0] : nil }
        /// Stations in the group with at least one free plug (never more than the group size).
        func freeStations(at now: Date = .now) -> Int { items.filter { $0.station.freeCount(at: now) > 0 }.count }
        /// Bounding span of the grouped stations (degrees).
        var latSpan: Double { (items.map(\.station.lat).max() ?? 0) - (items.map(\.station.lat).min() ?? 0) }
        var lngSpan: Double { (items.map(\.station.lng).max() ?? 0) - (items.map(\.station.lng).min() ?? 0) }
    }

    /// Below this visible height (degrees, ~1.3 km) every station gets its own pin.
    static let expandSpan = 0.012

    /// Groups the visible stations into a coarse screen grid (about 5 across and
    /// 8 down a portrait phone), so a crowded city shows a few count bubbles
    /// that split up as you zoom in. Zoomed in past `expandSpan`, or for the
    /// selected station, nothing is grouped.
    static func clusters(_ items: [Item], region: Region?, selectedId: String?, columns: Double = 5, rows: Double = 8) -> [Cluster] {
        guard let region else { return items.prefix(150).map { Cluster(items: [$0], center: $0.station.latLng) } }
        let visible = items.filter { region.contains($0.station.latLng) || $0.id == selectedId }
        if region.latSpan <= expandSpan || region.latSpan <= 0 || region.lngSpan <= 0 {
            return visible.map { Cluster(items: [$0], center: $0.station.latLng) }
        }
        let latCell = region.latSpan / rows, lngCell = region.lngSpan / columns
        var cells: [Int64: [Item]] = [:]
        var order: [Int64] = []
        var result: [Cluster] = []
        for item in visible {
            if item.id == selectedId {
                result.append(Cluster(items: [item], center: item.station.latLng))
                continue
            }
            // Anchored to the world grid, not the camera, so cells don't reshuffle on every small pan.
            let row = Int64((item.station.lat / latCell).rounded(.down))
            let col = Int64((item.station.lng / lngCell).rounded(.down))
            let key = row &* 1_000_003 &+ col
            if cells[key] == nil { order.append(key) }
            cells[key, default: []].append(item)
        }
        for key in order {
            let group = cells[key]!
            let lat = group.reduce(0) { $0 + $1.station.lat } / Double(group.count)
            let lng = group.reduce(0) { $0 + $1.station.lng } / Double(group.count)
            result.append(Cluster(items: group, center: group.count == 1 ? group[0].station.latLng : LatLng(lat: lat, lng: lng)))
        }
        return result
    }
}
