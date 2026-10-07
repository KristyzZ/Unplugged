import Foundation

enum Geo {
    /// Roads are longer than straight lines; rough Lithuania-wide factor.
    static let roadFactor = 1.2

    static func haversineKm(_ a: LatLng, _ b: LatLng) -> Double {
        let r = 6371.0
        let toRad = { (d: Double) in d * .pi / 180 }
        let dLat = toRad(b.lat - a.lat)
        let dLng = toRad(b.lng - a.lng)
        let h = pow(sin(dLat / 2), 2) + cos(toRad(a.lat)) * cos(toRad(b.lat)) * pow(sin(dLng / 2), 2)
        return 2 * r * asin(sqrt(h))
    }

    static func roadKm(_ a: LatLng, _ b: LatLng) -> Double {
        haversineKm(a, b) * roadFactor
    }

    /// Where `p` sits along the straight line a→b. `t` is 0 at a and 1 at b;
    /// `detourKm` is the extra straight-line distance to pass through p.
    static func positionAlong(_ a: LatLng, _ b: LatLng, _ p: LatLng) -> (t: Double, detourKm: Double) {
        let direct = haversineKm(a, b)
        let ap = haversineKm(a, p)
        let pb = haversineKm(p, b)
        let t = (ap + pb) == 0 ? 0 : ap / (ap + pb)
        return (t, ap + pb - direct)
    }
}
