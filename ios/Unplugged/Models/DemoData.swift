import Foundation

// Demo data. Operator names are real Lithuanian networks, but every station,
// price, connector count and occupancy figure here is made up for the prototype.
// Replace with operator APIs (OCPI) or a backend when available.

/// Small deterministic PRNG (FNV-1a seed + mulberry32) so demo data is stable.
struct SeededRandom {
    private var state: UInt32

    init(_ seed: String) {
        var h: UInt32 = 2_166_136_261
        for byte in seed.utf8 {
            h ^= UInt32(byte)
            h = h &* 16_777_619
        }
        state = h
    }

    /// Next value in [0, 1).
    mutating func next() -> Double {
        state = state &+ 0x6D2B_79F5
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

enum DemoData {
    static let operators: [ChargeOperator] = [
        ChargeOperator(id: "ignitis", name: "Ignitis ON", colorHex: "0F766E"),
        ChargeOperator(id: "eleport", name: "Eleport", colorHex: "7C3AED"),
        ChargeOperator(id: "enefit", name: "Enefit Volt", colorHex: "EA580C"),
        ChargeOperator(id: "inbalance", name: "Inbalance grid", colorHex: "2563EB"),
    ]

    static func chargeOperator(_ id: String) -> ChargeOperator {
        operators.first { $0.id == id } ?? ChargeOperator(id: id, name: id, colorHex: "64748B")
    }

    enum Profile { case mall, office, residential, highway, transport }

    /// Base occupancy shape per hour (0–23) for each location type.
    static let profiles: [Profile: [Double]] = [
        .mall: [0.05, 0.03, 0.02, 0.02, 0.02, 0.05, 0.1, 0.2, 0.35, 0.5, 0.65, 0.75, 0.8, 0.8, 0.78, 0.8, 0.85, 0.9, 0.9, 0.8, 0.6, 0.4, 0.2, 0.1],
        .office: [0.05, 0.05, 0.05, 0.05, 0.05, 0.1, 0.25, 0.6, 0.9, 0.95, 0.95, 0.9, 0.85, 0.9, 0.9, 0.85, 0.7, 0.45, 0.25, 0.15, 0.1, 0.08, 0.05, 0.05],
        .residential: [0.7, 0.75, 0.75, 0.75, 0.7, 0.6, 0.45, 0.3, 0.2, 0.15, 0.15, 0.15, 0.2, 0.2, 0.2, 0.25, 0.35, 0.55, 0.7, 0.8, 0.85, 0.85, 0.8, 0.75],
        .highway: [0.1, 0.05, 0.05, 0.05, 0.1, 0.2, 0.35, 0.45, 0.5, 0.55, 0.6, 0.7, 0.75, 0.7, 0.65, 0.7, 0.8, 0.85, 0.75, 0.6, 0.45, 0.3, 0.2, 0.15],
        .transport: [0.2, 0.15, 0.1, 0.1, 0.15, 0.3, 0.55, 0.7, 0.75, 0.7, 0.65, 0.65, 0.6, 0.6, 0.65, 0.7, 0.75, 0.7, 0.6, 0.5, 0.4, 0.35, 0.3, 0.25],
    ]

    struct Seed {
        let id: String
        let name: String
        let address: String
        let city: String
        let lat: Double
        let lng: Double
        let operatorId: String
        let profile: Profile
        /// (type, powerKw, count)
        let connectors: [(ConnectorType, Double, Int)]
        var amenities: [String] = []
    }

    static let seeds: [Seed] = [
        // Vilnius
        Seed(id: "akropolis", name: "Akropolis", address: "Ozo g. 25", city: "Vilnius", lat: 54.7106, lng: 25.2627, operatorId: "ignitis", profile: .mall, connectors: [(.ccs2, 150, 2), (.type2, 22, 4)], amenities: ["Shops", "Café", "WC"]),
        Seed(id: "ozas", name: "Ozas", address: "Ozo g. 18", city: "Vilnius", lat: 54.7155, lng: 25.279, operatorId: "eleport", profile: .mall, connectors: [(.ccs2, 120, 2), (.type2, 22, 2)], amenities: ["Shops", "Café"]),
        Seed(id: "europa", name: "Europa", address: "Konstitucijos pr. 7A", city: "Vilnius", lat: 54.6964, lng: 25.2775, operatorId: "enefit", profile: .office, connectors: [(.ccs2, 60, 2), (.type2, 11, 4)], amenities: ["Shops", "WC"]),
        Seed(id: "panorama", name: "Panorama", address: "Saltoniškių g. 9", city: "Vilnius", lat: 54.699, lng: 25.2585, operatorId: "ignitis", profile: .mall, connectors: [(.ccs2, 100, 2), (.type2, 22, 2)], amenities: ["Shops", "Café"]),
        Seed(id: "senamiestis", name: "Lukiškės Square", address: "Gedimino pr. 40", city: "Vilnius", lat: 54.6895, lng: 25.27, operatorId: "inbalance", profile: .office, connectors: [(.type2, 22, 4)]),
        Seed(id: "oro-uostas", name: "Airport", address: "Rodūnios kl. 10A", city: "Vilnius", lat: 54.639, lng: 25.286, operatorId: "ignitis", profile: .transport, connectors: [(.ccs2, 150, 2), (.type2, 22, 4)], amenities: ["Café", "WC"]),
        Seed(id: "stotis", name: "Railway Station", address: "Geležinkelio g. 16", city: "Vilnius", lat: 54.67, lng: 25.284, operatorId: "eleport", profile: .transport, connectors: [(.ccs2, 60, 2), (.type2, 22, 2)]),
        Seed(id: "antakalnis", name: "Antakalnis", address: "Antakalnio g. 54", city: "Vilnius", lat: 54.702, lng: 25.315, operatorId: "enefit", profile: .residential, connectors: [(.ccs2, 50, 1), (.type2, 22, 2)]),
        Seed(id: "zirmunai", name: "Žirmūnai", address: "Žirmūnų g. 64", city: "Vilnius", lat: 54.711, lng: 25.301, operatorId: "inbalance", profile: .residential, connectors: [(.ccs2, 50, 1), (.type2, 11, 3)]),
        Seed(id: "pasilaiciai", name: "Pašilaičiai", address: "Gabijos g. 86", city: "Vilnius", lat: 54.734, lng: 25.224, operatorId: "ignitis", profile: .residential, connectors: [(.ccs2, 75, 2), (.type2, 22, 2)]),
        Seed(id: "ukmerges", name: "Ukmergė Business Center", address: "Ukmergės g. 280", city: "Vilnius", lat: 54.73, lng: 25.24, operatorId: "eleport", profile: .office, connectors: [(.ccs2, 120, 2), (.type2, 22, 4)]),
        Seed(id: "pilaite", name: "Pilaitė", address: "Pilaitės pr. 16", city: "Vilnius", lat: 54.709, lng: 25.183, operatorId: "enefit", profile: .residential, connectors: [(.ccs2, 50, 1), (.type2, 22, 2)]),
        Seed(id: "lazdynai", name: "Lazdynai", address: "Architektų g. 19", city: "Vilnius", lat: 54.675, lng: 25.208, operatorId: "inbalance", profile: .residential, connectors: [(.type2, 22, 2)]),
        Seed(id: "santariskes", name: "Santariškės", address: "Santariškių g. 2", city: "Vilnius", lat: 54.7395, lng: 25.273, operatorId: "ignitis", profile: .office, connectors: [(.ccs2, 60, 2), (.type2, 22, 4)]),
        Seed(id: "paupys", name: "Paupys", address: "Paupio g. 46", city: "Vilnius", lat: 54.68, lng: 25.3, operatorId: "eleport", profile: .office, connectors: [(.ccs2, 100, 1), (.type2, 22, 2)], amenities: ["Café"]),
        Seed(id: "naujoji-vilnia", name: "Naujoji Vilnia", address: "Parko g. 2", city: "Vilnius", lat: 54.695, lng: 25.41, operatorId: "enefit", profile: .residential, connectors: [(.ccs2, 50, 1), (.chademo, 50, 1)]),
        // Intercity / highway corridors
        Seed(id: "elektrenai", name: "Elektrėnai A1", address: "A1 magistralė, 47 km", city: "Elektrėnai", lat: 54.786, lng: 24.661, operatorId: "ignitis", profile: .highway, connectors: [(.ccs2, 300, 4), (.chademo, 50, 1)], amenities: ["Café", "WC"]),
        Seed(id: "kaunas-centras", name: "Kaunas Center", address: "Laisvės al. 100", city: "Kaunas", lat: 54.8985, lng: 23.9036, operatorId: "eleport", profile: .office, connectors: [(.ccs2, 100, 2), (.type2, 22, 4)]),
        Seed(id: "kaunas-mega", name: "Mega", address: "Islandijos pl. 32", city: "Kaunas", lat: 54.93, lng: 23.905, operatorId: "ignitis", profile: .mall, connectors: [(.ccs2, 150, 4), (.type2, 22, 4)], amenities: ["Shops", "Café", "WC"]),
        Seed(id: "raseiniai", name: "Raseiniai A1", address: "A1 magistralė, 140 km", city: "Raseiniai", lat: 55.374, lng: 23.122, operatorId: "enefit", profile: .highway, connectors: [(.ccs2, 150, 2)], amenities: ["Café", "WC"]),
        Seed(id: "klaipeda", name: "Klaipėda Akropolis", address: "Taikos pr. 61", city: "Klaipėda", lat: 55.7033, lng: 21.1443, operatorId: "ignitis", profile: .mall, connectors: [(.ccs2, 150, 2), (.type2, 22, 4)]),
        Seed(id: "palanga", name: "Palanga", address: "Vytauto g. 106", city: "Palanga", lat: 55.9175, lng: 21.0686, operatorId: "eleport", profile: .mall, connectors: [(.ccs2, 60, 2), (.type2, 22, 2)]),
        Seed(id: "ukmerge", name: "Ukmergė A2", address: "A2 magistralė, 75 km", city: "Ukmergė", lat: 55.245, lng: 24.76, operatorId: "inbalance", profile: .highway, connectors: [(.ccs2, 120, 2)], amenities: ["Café"]),
        Seed(id: "panevezys", name: "Panevėžys Babilonas", address: "J. Biliūno g. 1", city: "Panevėžys", lat: 55.7348, lng: 24.3575, operatorId: "ignitis", profile: .mall, connectors: [(.ccs2, 150, 2), (.type2, 22, 2)]),
        Seed(id: "siauliai", name: "Šiauliai Saulės miestas", address: "Aido g. 8", city: "Šiauliai", lat: 55.9349, lng: 23.3137, operatorId: "enefit", profile: .mall, connectors: [(.ccs2, 100, 2), (.type2, 22, 2)]),
        Seed(id: "bauska", name: "Bauska (LV)", address: "A7, Bauska", city: "Bauska", lat: 56.408, lng: 24.193, operatorId: "enefit", profile: .highway, connectors: [(.ccs2, 150, 2)]),
        Seed(id: "utena", name: "Utena", address: "Utenio a. 1", city: "Utena", lat: 55.4977, lng: 25.5992, operatorId: "inbalance", profile: .residential, connectors: [(.ccs2, 50, 1), (.type2, 22, 2)]),
        Seed(id: "alytus", name: "Alytus", address: "Naujoji g. 2", city: "Alytus", lat: 54.3963, lng: 24.0459, operatorId: "eleport", profile: .mall, connectors: [(.ccs2, 60, 2), (.type2, 22, 2)]),
        Seed(id: "druskininkai", name: "Druskininkai", address: "Vilniaus al. 10", city: "Druskininkai", lat: 54.017, lng: 23.97, operatorId: "ignitis", profile: .mall, connectors: [(.ccs2, 100, 2), (.type2, 22, 2)]),
        Seed(id: "marijampole", name: "Marijampolė Via Baltica", address: "A5, Marijampolė", city: "Marijampolė", lat: 54.559, lng: 23.354, operatorId: "enefit", profile: .highway, connectors: [(.ccs2, 150, 2)]),
    ]

    static let basePrice: [String: Double] = ["ignitis": 0.49, "eleport": 0.45, "enefit": 0.47, "inbalance": 0.42]

    private static func buildConnectors(_ seed: Seed, rand: inout SeededRandom, occupancyNow: Double, provenance: Provenance) -> [Connector] {
        var out: [Connector] = []
        for (type, power, count) in seed.connectors {
            for _ in 0..<count {
                let r = rand.next()
                var status: ConnectorStatus = .available
                if r < occupancyNow * 0.75 { status = .charging }
                else if r < occupancyNow * 0.93 { status = .idle }
                else if r < occupancyNow { status = .blocked }
                if rand.next() < 0.04 { status = .offline }
                let idle = status == .idle ? Int(3 + rand.next() * 40) : nil
                let eta = status == .charging ? Int(5 + rand.next() * (power >= 50 ? 35 : 150)) : nil
                out.append(Connector(id: "\(seed.id)-\(out.count + 1)", type: type, powerKw: power, status: status, idleMinutes: idle, etaMinutes: eta, provenance: provenance))
            }
        }
        return out
    }

    private static func buildStation(_ seed: Seed, hour: Int, tick: Int, observedAt: Date) -> Station {
        var rand = SeededRandom(seed.id)
        let base = profiles[seed.profile] ?? Array(repeating: 0.5, count: 24)
        let hourly = base.map { v in min(1, max(0, v + (rand.next() - 0.5) * 0.2)) }
        let hasFastDC = seed.connectors.contains { $0.0.isDC && $0.1 >= 100 }
        let raw = (basePrice[seed.operatorId] ?? 0.45) + (hasFastDC ? 0.1 : 0) + (rand.next() - 0.5) * 0.06
        let price = (raw * 100).rounded() / 100
        // Connector states depend on the hour and a "tick" so the map changes over time.
        var live = SeededRandom("\(seed.id):\(hour):\(tick)")
        return Station(
            id: seed.id, name: trKey(seed.name), address: seed.address, city: seed.city,
            lat: seed.lat, lng: seed.lng, operatorId: seed.operatorId, pricePerKwh: price,
            connectors: buildConnectors(seed, rand: &live, occupancyNow: hourly[hour], provenance: .demo(at: observedAt)),
            hourlyOccupancy: hourly, amenities: seed.amenities.map(trKey),
            priceProvenance: .demo(at: observedAt, source: "Demo tariff"),
            // Every demo station is simulated as fully integrated, so the whole demo story works.
            // Real stations (#35) get their real level and are never marked simulated.
            capabilities: .demo(.fullCharging)
        )
    }

    /// Snapshot of all stations. `tick` simulates real-time updates
    /// (increment it every ~20 s to reshuffle statuses).
    static func stations(at date: Date = .now, tick: Int = 0) -> [Station] {
        let hour = Calendar.current.component(.hour, from: date)
        return seeds.map { buildStation($0, hour: hour, tick: tick, observedAt: date) }
    }

    // MARK: Vehicles & places

    /// Approximate real-world figures; good enough for planning demos.
    static let vehicles: [Vehicle] = [
        Vehicle(id: "model-y", name: "Tesla Model Y LR", batteryKwh: 75, consumptionKwhPer100: 17, maxDcKw: 250, maxAcKw: 11, connectors: [.ccs2, .type2]),
        Vehicle(id: "model-3", name: "Tesla Model 3 RWD", batteryKwh: 57, consumptionKwhPer100: 15, maxDcKw: 170, maxAcKw: 11, connectors: [.ccs2, .type2]),
        Vehicle(id: "id4", name: "Volkswagen ID.4 Pro", batteryKwh: 77, consumptionKwhPer100: 19, maxDcKw: 135, maxAcKw: 11, connectors: [.ccs2, .type2]),
        Vehicle(id: "ioniq5", name: "Hyundai Ioniq 5 LR", batteryKwh: 77, consumptionKwhPer100: 19, maxDcKw: 230, maxAcKw: 11, connectors: [.ccs2, .type2]),
        Vehicle(id: "ev3", name: "Kia EV3 LR", batteryKwh: 81, consumptionKwhPer100: 16, maxDcKw: 128, maxAcKw: 11, connectors: [.ccs2, .type2]),
        Vehicle(id: "enyaq", name: "Škoda Enyaq 85", batteryKwh: 77, consumptionKwhPer100: 18, maxDcKw: 135, maxAcKw: 11, connectors: [.ccs2, .type2]),
        Vehicle(id: "leaf", name: "Nissan Leaf 40", batteryKwh: 39, consumptionKwhPer100: 17, maxDcKw: 50, maxAcKw: 6.6, connectors: [.chademo, .type2]),
        Vehicle(id: "dolphin", name: "BYD Dolphin", batteryKwh: 60, consumptionKwhPer100: 16, maxDcKw: 88, maxAcKw: 11, connectors: [.ccs2, .type2]),
    ]

    static func vehicle(_ id: String) -> Vehicle {
        vehicles.first { $0.id == id } ?? vehicles[0]
    }

    static var places: [Place] { [
        Place(id: "vilnius", name: "Vilnius (center)", lat: 54.6872, lng: 25.2797),
        Place(id: "kaunas", name: "Kaunas", lat: 54.8985, lng: 23.9036),
        Place(id: "klaipeda", name: "Klaipėda", lat: 55.7033, lng: 21.1443),
        Place(id: "palanga", name: "Palanga", lat: 55.9175, lng: 21.0686),
        Place(id: "panevezys", name: "Panevėžys", lat: 55.7348, lng: 24.3575),
        Place(id: "siauliai", name: "Šiauliai", lat: 55.9349, lng: 23.3137),
        Place(id: "druskininkai", name: "Druskininkai", lat: 54.017, lng: 23.97),
        Place(id: "utena", name: "Utena", lat: 55.4977, lng: 25.5992),
        Place(id: "marijampole", name: "Marijampolė", lat: 54.559, lng: 23.354),
        Place(id: "riga", name: "Riga (LV)", lat: 56.9496, lng: 24.1052),
    ].map { Place(id: $0.id, name: trKey($0.name), lat: $0.lat, lng: $0.lng) } }

    static let vilniusCenter = LatLng(lat: 54.6872, lng: 25.2797)

    // MARK: Profile (fictional payment methods and operator plans)

    struct PaymentMethod: Identifiable, Hashable {
        let id: String
        let title: String
        let detail: String
        let systemImage: String
    }

    static var paymentMethods: [PaymentMethod] { [
        PaymentMethod(id: "visa", title: "Visa •••• 4242", detail: tr("Card"), systemImage: "creditcard"),
        PaymentMethod(id: "applepay", title: "Apple Pay", detail: tr("Wallet"), systemImage: "apple.logo"),
        PaymentMethod(id: "sepa", title: "SEPA •••• 1187", detail: tr("Bank account"), systemImage: "building.columns"),
    ] }

    struct OperatorPlan: Identifiable, Hashable {
        let id: String        // operator id
        let name: String
        let perk: String
    }

    static var plans: [OperatorPlan] { [
        OperatorPlan(id: "ignitis", name: "Ignitis ON Plus", perk: tr("−10 % on energy")),
        OperatorPlan(id: "eleport", name: "Eleport Flex", perk: tr("No session start fee")),
        OperatorPlan(id: "enefit", name: "Enefit Volt Member", perk: tr("−8 % on energy")),
        OperatorPlan(id: "inbalance", name: "Inbalance Pass", perk: tr("−12 % on AC charging")),
    ] }
}
