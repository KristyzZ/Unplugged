import Foundation
@testable import Unplugged

/// Small, explicit builders so tests state only what they care about.
/// Add new builders here (or in a sibling file) rather than copying setup into tests.
enum Fixtures {
    /// A fixed instant: tests never read the wall clock.
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static func at(minutes: Double, from base: Date = t0) -> Date {
        base.addingTimeInterval(minutes * 60)
    }

    static let vilnius = LatLng(lat: 54.6872, lng: 25.2797)
    static let kaunas = LatLng(lat: 54.8985, lng: 23.9036)
    static let klaipeda = LatLng(lat: 55.7033, lng: 21.1443)

    /// Point `t` (0...1) of the way along the straight line a → b.
    static func point(_ t: Double, from a: LatLng, to b: LatLng) -> LatLng {
        LatLng(lat: a.lat + (b.lat - a.lat) * t, lng: a.lng + (b.lng - a.lng) * t)
    }

    static func vehicle(
        battery: Double = 60,
        consumption: Double = 15,
        maxDc: Double = 150,
        maxAc: Double = 11,
        connectors: [ConnectorType] = [.ccs2, .type2]
    ) -> Vehicle {
        Vehicle(id: "test-ev", name: "Test EV", batteryKwh: battery, consumptionKwhPer100: consumption,
                maxDcKw: maxDc, maxAcKw: maxAc, connectors: connectors)
    }

    /// A connector whose status was reported `ageMinutes` before `Fixtures.t0` (fresh by default).
    static func connector(
        _ type: ConnectorType = .ccs2,
        kw: Double = 150,
        status: ConnectorStatus = .available,
        id: String = "c1",
        ageMinutes: Double = 0,
        dataClass: DataClass = .observed
    ) -> Connector {
        Connector(id: id, type: type, powerKw: kw, status: status,
                  provenance: Provenance(source: "Test feed", timestamp: at(minutes: -ageMinutes), dataClass: dataClass))
    }

    static func station(
        _ id: String,
        at location: LatLng,
        connectors: [Connector]? = nil,
        price: Double = 0.5,
        occupancy: Double = 0.3,
        hourlyOccupancy: [Double]? = nil,
        capabilities: StationCapabilities = .demo()
    ) -> Station {
        Station(
            id: id, name: id, address: "", city: "Test",
            lat: location.lat, lng: location.lng, operatorId: "test", pricePerKwh: price,
            connectors: connectors ?? [connector()],
            hourlyOccupancy: hourlyOccupancy ?? Array(repeating: occupancy, count: 24), amenities: [],
            priceProvenance: Provenance(source: "Test feed", timestamp: t0, dataClass: .observed),
            capabilities: capabilities
        )
    }

    /// Stations spaced evenly along a → b (exclusive of the ends).
    static func corridor(from a: LatLng, to b: LatLng, count: Int, connectors: [Connector]? = nil) -> [Station] {
        (1...count).map { i in
            station("s\(i)", at: point(Double(i) / Double(count + 1), from: a, to: b), connectors: connectors)
        }
    }

    /// 30 min charge from 20 % to 80 %, 10 min grace, started at `t0`.
    static func session(minutesToTarget: Double = 30, grace: Int = 10) -> ChargingSession {
        ChargingSession(
            stationId: "s1", stationName: "Test", connectorLabel: "CCS2 · 150 kW", startedAt: t0,
            startSoc: 20, targetSoc: 80, minutesToTarget: minutesToTarget, graceMinutes: grace,
            pricePerKwh: 0.5, batteryKwh: 60
        )
    }
}
