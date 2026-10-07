import CoreLocation
import Foundation

// Core domain types for the Unplugged EV charging platform.

enum ConnectorType: String, Codable, CaseIterable, Hashable {
    case ccs2 = "CCS2"
    case type2 = "Type2"
    case chademo = "CHAdeMO"

    /// Everything except Type2 is DC fast charging.
    var isDC: Bool { self != .type2 }
}

enum ConnectorStatus: String, Codable, Hashable {
    case available   // free and ready
    case charging    // car plugged in and drawing power
    case idle        // charging finished, car still occupying the spot
    case blocked     // spot taken by a car that is not charging / not an EV
    case offline     // out of service
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

    var latLng: LatLng { LatLng(lat: lat, lng: lng) }
    var coordinate: CLLocationCoordinate2D { latLng.coordinate }
}

struct Vehicle: Identifiable, Hashable {
    let id: String
    let name: String
    let batteryKwh: Double
    /// Real-world consumption in kWh per 100 km.
    let consumptionKwhPer100: Double
    let maxDcKw: Double
    let maxAcKw: Double
    let connectors: [ConnectorType]

    /// Approximate range in km at a given state of charge (%).
    func rangeKm(soc: Double) -> Double {
        soc / 100 * batteryKwh / consumptionKwhPer100 * 100
    }
}

struct Place: Identifiable, Hashable {
    let id: String
    let name: String
    let lat: Double
    let lng: Double

    var latLng: LatLng { LatLng(lat: lat, lng: lng) }
}
