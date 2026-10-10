import Foundation

/// Made-up busy hours for stations that have no history yet (the live registry
/// has none). The shape comes from what the place looks like (a shop, an
/// office, a motorway stop, a home area) and is nudged per station so that
/// neighbours don't look identical. The station page labels it as an estimate.
enum EstimatedOccupancy {
    static func hourly(id: String, name: String, address: String) -> [Double] {
        let profile = profile(for: "\(name) \(address)".lowercased())
        let base = DemoData.profiles[profile] ?? Array(repeating: 0.3, count: 24)
        let seed = stableHash(id)
        let scale = 0.65 + Double(seed % 40) / 100        // 0.65 … 1.04
        let shift = Int((seed / 40) % 3) - 1              // peak an hour earlier, same or later
        return (0..<24).map { h in
            let v = base[((h - shift) % 24 + 24) % 24] * scale
            let wobble = Double((seed >> (h % 16)) & 7) / 100 - 0.035
            return min(0.97, max(0.02, ((v + wobble) * 100).rounded() / 100))
        }
    }

    static func profile(for text: String) -> DemoData.Profile {
        let rules: [(DemoData.Profile, [String])] = [
            (.mall, ["norfa", "maxima", "rimi", "iki", "lidl", "akropolis", "panorama", "ozas", "ikea", "mega",
                     "prekybos", "pc ", "outlet", "senukai", "depo", "mall"]),
            (.highway, ["a1", "a2", "a5", "a12", "kelias", "magistral", "circle k", "viada", "orlen", "neste", "degalin"]),
            (.transport, ["stotis", "oro uost", "airport", "station", "autobus", "geležinkel"]),
            (.office, ["verslo", "biuras", "office", "business", "centras", "plaza", "tower", "bokšt"]),
        ]
        for (profile, words) in rules where words.contains(where: text.contains) { return profile }
        return .residential
    }

    /// FNV-1a: the same id always gives the same pattern (Swift's hashValue changes per launch).
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }
}
