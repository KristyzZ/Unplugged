import Foundation

// Private charger sharing: homeowners and charging-station owners list their
// own charger, and drivers book it like any other station. Pricing is
// suggested from the public stations around the charger.

/// Who is listing the charger. Only owners can list: a home charger by the
/// homeowner, a business charger by the station's owner.
enum HostKind: String, Codable, CaseIterable, Identifiable {
    case homeowner
    case stationOwner

    var id: String { rawValue }
}

/// Extras a guest gets with the spot.
enum HostAmenity: String, Codable, CaseIterable, Identifiable {
    case covered, cable, lit, cctv, wifi, wc

    var id: String { rawValue }
}

/// When the charger can be booked: chosen weekdays and a daily time window.
/// A window that ends before it starts runs overnight (18:00–08:00).
struct HostSchedule: Codable, Hashable {
    /// ISO weekdays, 1 = Monday … 7 = Sunday.
    var days: Set<Int> = Set(1...7)
    var fromHour = 0
    var toHour = 24

    static let always = HostSchedule()
    static let evenings = HostSchedule(days: Set(1...7), fromHour: 18, toHour: 8)
    static let workdays = HostSchedule(days: Set(1...5), fromHour: 8, toHour: 18)

    var isAllDay: Bool { fromHour == toHour || (fromHour == 0 && toHour == 24) }

    var hoursPerDay: Int {
        if isAllDay { return 24 }
        return toHour > fromHour ? toHour - fromHour : 24 - fromHour + toHour
    }

    var hoursPerWeek: Int { hoursPerDay * days.count }

    /// Open at this moment. An overnight window belongs to the day it starts.
    func isOpen(at date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        let day = Self.isoWeekday(date, calendar: calendar)
        if isAllDay { return days.contains(day) }
        if toHour > fromHour { return days.contains(day) && hour >= fromHour && hour < toHour }
        if hour >= fromHour { return days.contains(day) }
        let yesterday = day == 1 ? 7 : day - 1
        return hour < toHour && days.contains(yesterday)
    }

    static func isoWeekday(_ date: Date, calendar: Calendar = .current) -> Int {
        // Calendar weekday: 1 = Sunday … 7 = Saturday.
        let w = calendar.component(.weekday, from: date)
        return w == 1 ? 7 : w - 1
    }
}

/// A charger a host offers to other drivers.
struct HostListing: Codable, Identifiable, Hashable {
    var id = "host-" + UUID().uuidString.prefix(8).lowercased()
    var kind: HostKind = .homeowner
    var title = ""
    var address = ""
    var city = ""
    var location = DemoData.vilniusCenter
    var connector: ConnectorType = .type2
    var powerKw: Double = 11
    /// Chargers at this place (a home has one; a business may have several).
    var spots = 1
    var pricePerKwh: Double = 0.35
    var schedule = HostSchedule.evenings
    /// Drivers can book straight away, without waiting for the host to accept.
    var instantBook = true
    var accessNotes = ""
    var amenities: Set<HostAmenity> = []
    /// JPEG in Application Support (HostPhotos), see HostPhotoStore.
    var photoFile: String?
    var paused = false
    var createdAt = Date()

    static let operatorId = "host"
}

/// What nearby public stations charge, and the price we suggest.
struct MarketQuote: Equatable {
    let low: Double
    let median: Double
    let high: Double
    let suggested: Double
    /// Public stations the quote is based on.
    let sampleCount: Int
    /// How far around the charger they were taken from (km).
    let radiusKm: Double
}

/// Rough monthly figures for a listing.
struct HostEarnings: Equatable {
    let sessionsPerMonth: Int
    let kwhPerMonth: Double
    /// What drivers pay.
    let grossEur: Double
    /// After the Unplugged service fee.
    let payoutEur: Double
    /// After the fee and the electricity you buy.
    let profitEur: Double
}

enum Hosting {
    /// Service fee kept from each booking.
    static let serviceFee = 0.15
    /// Typical Lithuanian household electricity price, €/kWh (used for the
    /// floor price and the profit estimate).
    static let homeEnergyCost = 0.24
    /// Lowest price we let a host set, so a session is never sold at a loss.
    static var minPrice: Double { ((homeEnergyCost / (1 - serviceFee)) * 100).rounded(.up) / 100 }
    static let maxPrice = 0.99

    /// Charger powers people actually install, AC then DC.
    static let powerOptions: [Double] = [3.7, 7.4, 11, 22, 50, 75, 150]

    /// Compare against stations within this distance first.
    static let marketRadiusKm = 10.0

    static func isFast(_ powerKw: Double) -> Bool { powerKw >= 50 }

    /// Prices of public stations of the same kind (AC or DC fast) around the
    /// charger. Falls back to every station when fewer than 3 are close.
    static func marketQuote(at location: LatLng, powerKw: Double, stations: [Station]) -> MarketQuote {
        let fast = isFast(powerKw)
        let similar = stations.filter { s in
            s.operatorId != HostListing.operatorId && s.connectors.contains { isFast($0.powerKw) == fast }
        }
        let near = similar.filter { Geo.haversineKm(location, $0.latLng) <= marketRadiusKm }
        let sample = near.count >= 3 ? near : similar
        let radius = near.count >= 3 ? marketRadiusKm : (sample.map { Geo.haversineKm(location, $0.latLng) }.max() ?? 0)
        let prices = sample.map(\.pricePerKwh).sorted()
        guard !prices.isEmpty else {
            let fallback = fast ? 0.55 : 0.45
            return MarketQuote(low: fallback, median: fallback, high: fallback,
                               suggested: suggest(median: fallback, fast: fast), sampleCount: 0, radiusKm: 0)
        }
        let mid = prices.count / 2
        let median = prices.count % 2 == 0 ? (prices[mid - 1] + prices[mid]) / 2 : prices[mid]
        return MarketQuote(low: prices[0], median: median, high: prices[prices.count - 1],
                           suggested: suggest(median: median, fast: fast), sampleCount: prices.count, radiusKm: radius)
    }

    /// A private charger can't offer what a public one does (shops, 24/7 access,
    /// several plugs), so it books best a little under the market: 10 % below
    /// for AC, 5 % for DC fast. Never below the floor price.
    static func suggest(median: Double, fast: Bool) -> Double {
        let price = median * (fast ? 0.95 : 0.9)
        return clampPrice((price * 100).rounded() / 100)
    }

    static func clampPrice(_ value: Double) -> Double {
        min(maxPrice, max(minPrice, value))
    }

    /// Where a price sits against the market: below, in line or above.
    enum Position { case below, inLine, above }

    static func position(of price: Double, in quote: MarketQuote) -> Position {
        if price < quote.median * 0.93 { return .below }
        if price > quote.median * 1.07 { return .above }
        return .inLine
    }

    /// Estimate from the open hours, how busy public chargers around are and the
    /// price. Cheaper than the market books more, pricier books less. Most cars
    /// take 11 kW on AC; a typical visit adds ~20 kWh on AC, ~30 kWh on DC.
    static func earnings(schedule: HostSchedule, powerKw: Double, spots: Int, price: Double,
                         quote: MarketQuote, nearbyOccupancy: Double) -> HostEarnings {
        let fast = isFast(powerKw)
        let hoursPerMonth = Double(schedule.hoursPerWeek) * 52 / 12
        let priceFactor = min(1.6, max(0.4, 1 + (quote.median - price) / max(quote.median, 0.01) * 2.5))
        // New private listings fill a fraction of what public stations nearby do.
        let uptake = min(0.6, max(0.02, nearbyOccupancy * (fast ? 0.35 : 0.25) * priceFactor))
        let kw = fast ? powerKw * 0.6 : min(powerKw, 11)
        let kwh = hoursPerMonth * uptake * kw * Double(max(1, spots))
        let perVisit = fast ? 30.0 : 20.0
        let gross = kwh * price
        let payout = gross * (1 - serviceFee)
        return HostEarnings(
            sessionsPerMonth: Int((kwh / perVisit).rounded()),
            kwhPerMonth: kwh,
            grossEur: gross,
            payoutEur: payout,
            profitEur: payout - kwh * homeEnergyCost
        )
    }

    /// Average occupancy (0–1) of public stations near a place.
    static func nearbyOccupancy(at location: LatLng, stations: [Station]) -> Double {
        let near = stations.filter {
            $0.operatorId != HostListing.operatorId && Geo.haversineKm(location, $0.latLng) <= marketRadiusKm
        }
        let pool = near.isEmpty ? stations.filter { $0.operatorId != HostListing.operatorId } : near
        guard !pool.isEmpty else { return 0.4 }
        return pool.map { $0.hourlyOccupancy.reduce(0, +) / 24 }.reduce(0, +) / Double(pool.count)
    }

    /// The listing as a station on the map: only while it's live and open.
    static func station(for listing: HostListing, at date: Date = .now) -> Station? {
        guard !listing.paused, listing.schedule.isOpen(at: date) else { return nil }
        let connectors = (0..<max(1, listing.spots)).map { i in
            Connector(id: "\(listing.id)-\(i + 1)", type: listing.connector, powerKw: listing.powerKw, status: .available)
        }
        let base = DemoData.profiles[.residential] ?? Array(repeating: 0.3, count: 24)
        return Station(
            id: listing.id, name: listing.title, address: listing.address, city: listing.city,
            lat: listing.location.lat, lng: listing.location.lng, operatorId: HostListing.operatorId,
            pricePerKwh: listing.pricePerKwh, connectors: connectors,
            hourlyOccupancy: base.map { $0 * 0.4 },
            amenities: listing.amenities.sorted { $0.rawValue < $1.rawValue }.map(\.title)
        )
    }
}

// MARK: Labels

extension HostKind {
    var title: String {
        switch self {
        case .homeowner: tr("Homeowner")
        case .stationOwner: tr("Charging station owner")
        }
    }

    var detail: String {
        switch self {
        case .homeowner: tr("A wallbox at your house or in your own parking space.")
        case .stationOwner: tr("Chargers your business owns: a hotel, shop, office or car park.")
        }
    }

    var systemImage: String {
        switch self {
        case .homeowner: "house.fill"
        case .stationOwner: "building.2.fill"
        }
    }
}

extension HostAmenity {
    var title: String {
        switch self {
        case .covered: tr("Covered parking")
        case .cable: tr("Cable provided")
        case .lit: tr("Well lit")
        case .cctv: tr("CCTV")
        case .wifi: tr("Wi-Fi")
        case .wc: tr("WC")
        }
    }

    var systemImage: String {
        switch self {
        case .covered: "parkingsign.circle.fill"
        case .cable: "cable.connector"
        case .lit: "lightbulb.fill"
        case .cctv: "video.fill"
        case .wifi: "wifi"
        case .wc: "toilet.fill"
        }
    }
}

extension HostSchedule {
    /// Short weekday names, Monday first.
    static var weekdaySymbols: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = L10n.locale
        let s = calendar.shortWeekdaySymbols
        return Array(s[1...]) + [s[0]]
    }

    /// "Every day, 18:00–08:00", "Mon–Fri, all day", "Mon, Wed, Sat, 08:00–18:00".
    var summary: String {
        let names = Self.weekdaySymbols
        let sorted = days.sorted()
        let dayText: String
        if sorted.count == 7 {
            dayText = tr("Every day")
        } else if sorted == Array(1...5) {
            dayText = "\(names[0])–\(names[4])"
        } else if sorted == [6, 7] {
            dayText = tr("Weekends")
        } else if sorted.isEmpty {
            dayText = tr("No days")
        } else {
            dayText = sorted.map { names[$0 - 1] }.joined(separator: ", ")
        }
        let hours = isAllDay ? tr("all day") : String(format: "%02d:00–%02d:00", fromHour, toHour % 24)
        return "\(dayText), \(hours)"
    }
}
