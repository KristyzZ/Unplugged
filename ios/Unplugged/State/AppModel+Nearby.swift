import Foundation
#if os(iOS)
import WidgetKit
#endif

/// Nearby fast chargers for the home-screen and Lock Screen widget.
extension AppModel {
    func setOrigin(_ value: LatLng) {
        guard Geo.haversineKm(value, origin) > 0.05 else { return }
        origin = value
        publishNearby()
    }

    /// Nearest stations with a free fast connector for your car. Falls back to
    /// the nearest fast ones when all are full.
    func nearbyFastChargers(limit: Int = 3) -> (stations: [(Station, Double)], anyFree: Bool) {
        let vehicle = self.vehicle
        let fast = stations.compactMap { s -> (Station, Double)? in
            guard s.connectors.contains(where: { $0.powerKw >= 50 && Charging.isCompatible(vehicle, $0) && $0.status != .offline }) else { return nil }
            return (s, Geo.haversineKm(origin, s.latLng))
        }
        .sorted { $0.1 < $1.1 }
        let free = fast.filter { s, _ in s.connectors.contains { $0.powerKw >= 50 && Charging.isCompatible(vehicle, $0) && $0.status == .available } }
        return free.isEmpty ? (Array(fast.prefix(limit)), false) : (Array(free.prefix(limit)), true)
    }

    /// Writes what the widget shows to the App Group and asks WidgetKit to
    /// redraw, but only when it changed in a way you'd notice (the reload
    /// budget is limited).
    func publishNearby() {
        #if os(iOS)
        let (nearby, anyFree) = nearbyFastChargers()
        let snapshot = NearbySnapshot(
            generatedAt: .now,
            chargers: nearby.map { s, km in
                NearbySnapshot.Charger(
                    id: s.id, name: s.name, address: s.address,
                    freeCount: s.freeCount, workingCount: s.workingCount,
                    maxKw: s.maxPower, pricePerKwh: s.pricePerKwh, distanceKm: km
                )
            },
            anyFree: anyFree,
            carName: vehicle.name,
            lang: lang.rawValue
        )
        snapshot.save()
        let changed = lastWidgetSnapshot.map {
            $0.chargers.map(\.id) != snapshot.chargers.map(\.id)
                || $0.chargers.map(\.freeCount) != snapshot.chargers.map(\.freeCount)
                || $0.lang != snapshot.lang || $0.carName != snapshot.carName
        } ?? true
        lastWidgetSnapshot = snapshot
        if changed || Date().timeIntervalSince(lastWidgetReload) > 15 * 60 {
            lastWidgetReload = Date()
            WidgetCenter.shared.reloadTimelines(ofKind: NearbySnapshot.widgetKind)
        }
        #endif
    }
}
