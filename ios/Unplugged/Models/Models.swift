import CoreLocation
import Foundation

// Core domain types for the Unplugged EV charging platform.

enum ConnectorType: String, Codable, CaseIterable, Hashable {
    case ccs2 = "CCS2"
    case type2 = "Type2"
    case chademo = "CHAdeMO"

    /// Everything except Type2 is DC fast charging.
    var isDC: Bool { self != .type2 }

    /// How the plug is usually written.
    var label: String {
        switch self {
        case .ccs2: "CCS2"
        case .type2: "Type 2"
        case .chademo: "CHAdeMO"
        }
    }
}

enum ConnectorStatus: String, Codable, Hashable {
    case unknown     // no trustworthy status (never reported, or too old). Not the same as available.
    case available   // free and ready
    case charging    // car plugged in and drawing power
    case idle        // charging finished, car still occupying the spot
    case blocked     // spot taken by a car that is not charging / not an EV
    case offline     // out of service
    case reserved    // held for the next driver in the queue (Unplugged handoff)
}

struct Connector: Identifiable, Hashable {
    let id: String
    let type: ConnectorType
    let powerKw: Double
    var status: ConnectorStatus
    /// Minutes the current occupant has been idle (only when status == .idle).
    var idleMinutes: Int?
    /// Estimated minutes until free (only when status == .charging).
    var etaMinutes: Int?
    /// Source, time and kind of data behind `status`. Defaults to "unspecified" (stale), so a
    /// status without provenance is never counted as confirmed.
    var provenance: Provenance = .unspecified
    /// What this connector costs, from the operator's tariff. nil for demo connectors (their price
    /// is the station's) and for connectors whose tariff is unknown.
    var tariff: ConnectorTariff? = nil
    /// When the charger last changed state, from the feed (local time converted). nil when unknown.
    var changedAt: Date? = nil
}

struct ChargeOperator: Identifiable, Hashable {
    let id: String
    let name: String
    let colorHex: String
}

struct LatLng: Hashable, Codable {
    var lat: Double
    var lng: Double

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) }
}

struct Station: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let city: String
    let lat: Double
    let lng: Double
    let operatorId: String
    /// Price per kWh in EUR.
    let pricePerKwh: Double
    var connectors: [Connector]
    /// Typical occupancy share (0–1) for each hour of the day, index 0 = 00:00.
    let hourlyOccupancy: [Double]
    let amenities: [String]
    /// Source, time and kind of data behind `pricePerKwh`.
    var priceProvenance: Provenance = .unspecified
    /// What the app may do with this station. Defaults to discovery only.
    var capabilities: StationCapabilities = .discoveryOnly

    var latLng: LatLng { LatLng(lat: lat, lng: lng) }
    var coordinate: CLLocationCoordinate2D { latLng.coordinate }

    /// False when no tariff gave this station a price: show "price unknown", not 0.
    var priceKnown: Bool { priceProvenance.timestamp != .distantPast }
}

/// An electric car model and what it can do. Loaded from the bundled Open EV
/// Data catalog (see VehicleCatalog).
struct Vehicle: Identifiable, Hashable, Codable {
    let id: String
    let brand: String
    let model: String
    let variant: String
    let year: Int?
    /// Usable battery capacity (kWh).
    let batteryKwh: Double
    /// Average real-world consumption in kWh per 100 km.
    let consumptionKwhPer100: Double
    let acKw: Double
    let acPhases: Int?
    /// 0 when the car can't fast-charge.
    let dcKw: Double
    let connectors: [ConnectorType]
    /// DC charging power by battery level: [[percent, kW]], covering 0–100 %.
    let curve: [[Double]]?
    /// Measured curve rather than a typical one.
    let curveMeasured: Bool?

    var name: String { [brand, model, variant].filter { !$0.isEmpty }.joined(separator: " ") }
    /// Model and variant without the brand.
    var title: String { [model, variant].filter { !$0.isEmpty }.joined(separator: " ") }

    var maxDcKw: Double { dcKw }
    var maxAcKw: Double { acKw }

    /// Approximate range in km at a given state of charge (%).
    func rangeKm(soc: Double) -> Double {
        soc / 100 * batteryKwh / consumptionKwhPer100 * 100
    }

    /// Most DC power the car takes at this battery level (kW), from its
    /// charging curve, or a typical taper when there is none.
    func dcPower(atSoc soc: Double) -> Double {
        guard let curve, curve.count >= 2 else { return dcKw * Charging.taper(soc) }
        let s = min(100, max(0, soc))
        for i in 1..<curve.count where s <= curve[i][0] {
            let (p0, k0) = (curve[i - 1][0], curve[i - 1][1])
            let (p1, k1) = (curve[i][0], curve[i][1])
            let t = p1 > p0 ? (s - p0) / (p1 - p0) : 0
            return k0 + (k1 - k0) * t
        }
        return curve[curve.count - 1][1]
    }
}

struct Place: Identifiable, Hashable {
    let id: String
    let name: String
    let lat: Double
    let lng: Double

    var latLng: LatLng { LatLng(lat: lat, lng: lng) }
}
