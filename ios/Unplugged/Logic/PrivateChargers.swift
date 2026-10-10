import Foundation

/// Demo community of private chargers (homeowners and small businesses) so the
/// map shows what sharing looks like: 50 across Lithuania, 30 of them in Vilnius.
/// Addresses are real streets; the listings themselves are invented.
enum PrivateChargers {
    private typealias Row = (id: String, area: String, address: String, city: String, lat: Double, lng: Double,
                             kind: HostKind, kw: Double, spots: Int, price: Double, schedule: HostSchedule,
                             amenities: Set<HostAmenity>)

    private static let rows: [Row] = [
        // Vilnius (30)
        ("pv01", "Žvėrynas", "Žvėryno g. 14", "Vilnius", 54.6935, 25.2584, .homeowner, 11, 1, 0.34, .evenings, [.cable]),
        ("pv02", "Antakalnis", "Antakalnio g. 61", "Vilnius", 54.7021, 25.3115, .homeowner, 7.4, 1, 0.31, .evenings, [.covered]),
        ("pv03", "Užupis", "Krivių g. 19", "Vilnius", 54.6795, 25.2985, .homeowner, 11, 1, 0.36, .always, [.lit]),
        ("pv04", "Šnipiškės", "Kalvarijų g. 38", "Vilnius", 54.7032, 25.2805, .homeowner, 11, 1, 0.33, .evenings, []),
        ("pv05", "Pašilaičiai", "Pašilaičių g. 8", "Vilnius", 54.7303, 25.2242, .homeowner, 7.4, 1, 0.29, .evenings, [.cable]),
        ("pv06", "Fabijoniškės", "Ateities g. 47", "Vilnius", 54.7349, 25.2491, .homeowner, 11, 1, 0.32, .always, [.lit]),
        ("pv07", "Justiniškės", "Justiniškių g. 72", "Vilnius", 54.7225, 25.2196, .homeowner, 7.4, 1, 0.30, .evenings, []),
        ("pv08", "Karoliniškės", "Loretos Asanavičiūtės g. 15", "Vilnius", 54.6873, 25.2093, .homeowner, 11, 1, 0.33, .evenings, [.covered]),
        ("pv09", "Lazdynai", "Architektų g. 102", "Vilnius", 54.6737, 25.2064, .homeowner, 11, 1, 0.31, .always, [.cable, .lit]),
        ("pv10", "Pilaitė", "Pilaitės pr. 30", "Vilnius", 54.7092, 25.1820, .homeowner, 22, 1, 0.37, .evenings, [.covered, .lit]),
        ("pv11", "Naujininkai", "Dariaus ir Girėno g. 54", "Vilnius", 54.6603, 25.2741, .homeowner, 7.4, 1, 0.28, .evenings, []),
        ("pv12", "Rasos", "Pelesos g. 9", "Vilnius", 54.6670, 25.3051, .homeowner, 11, 1, 0.35, .always, [.cable]),
        ("pv13", "Baltupiai", "Baltupio g. 121", "Vilnius", 54.7339, 25.2854, .homeowner, 11, 1, 0.32, .evenings, [.lit]),
        ("pv14", "Verkiai", "Jeruzalės g. 33", "Vilnius", 54.7480, 25.2905, .homeowner, 7.4, 1, 0.30, .evenings, []),
        ("pv15", "Santariškės", "Santariškių g. 12", "Vilnius", 54.7652, 25.2731, .homeowner, 11, 1, 0.33, .workdays, [.cable]),
        ("pv16", "Žirmūnai", "Žirmūnų g. 88", "Vilnius", 54.7150, 25.3010, .homeowner, 11, 1, 0.34, .always, [.covered, .cctv]),
        ("pv17", "Naujamiestis", "Kauno g. 22", "Vilnius", 54.6780, 25.2700, .homeowner, 7.4, 1, 0.33, .evenings, []),
        ("pv18", "Senamiestis", "Pylimo g. 41", "Vilnius", 54.6797, 25.2783, .homeowner, 11, 1, 0.39, .always, [.covered, .cctv]),
        ("pv19", "Viršuliškės", "Viršuliškių g. 36", "Vilnius", 54.7108, 25.2240, .homeowner, 7.4, 1, 0.29, .evenings, [.lit]),
        ("pv20", "Šeškinė", "Šeškinės g. 59", "Vilnius", 54.7176, 25.2475, .homeowner, 11, 1, 0.31, .evenings, []),
        ("pv21", "Valakampiai", "Valakampių g. 17", "Vilnius", 54.7238, 25.3398, .homeowner, 22, 1, 0.36, .always, [.cable]),
        ("pv22", "Pavilnys", "Pavilnio g. 44", "Vilnius", 54.6747, 25.3492, .homeowner, 7.4, 1, 0.28, .evenings, [.covered]),
        ("pv23", "Bajorai", "Bajorų kel. 6", "Vilnius", 54.7496, 25.2618, .homeowner, 11, 1, 0.32, .evenings, [.cable]),
        ("pv24", "Konstitucijos pr.", "Konstitucijos pr. 20", "Vilnius", 54.6966, 25.2722, .stationOwner, 22, 2, 0.42, .always, [.lit, .cctv, .wc, .wifi]),
        ("pv25", "Žalgirio g.", "Žalgirio g. 135", "Vilnius", 54.7055, 25.2673, .stationOwner, 22, 4, 0.40, .workdays, [.covered, .cctv, .wc]),
        ("pv26", "Gedimino pr.", "Gedimino pr. 9", "Vilnius", 54.6873, 25.2830, .stationOwner, 22, 2, 0.44, .always, [.wifi, .wc]),
        ("pv27", "Šiaurės miestelis", "Kareivių g. 11", "Vilnius", 54.7253, 25.2965, .stationOwner, 50, 2, 0.48, .workdays, [.covered, .cctv, .wc]),
        ("pv28", "Ozas", "Ozo g. 14", "Vilnius", 54.7134, 25.2788, .stationOwner, 22, 3, 0.41, .always, [.lit, .wc]),
        ("pv29", "Grigiškės", "Vilniaus g. 112", "Vilnius", 54.6779, 25.0868, .homeowner, 7.4, 1, 0.27, .evenings, []),
        ("pv30", "Trakų Vokė", "Žalioji g. 18", "Vilnius", 54.6372, 25.1210, .homeowner, 11, 1, 0.30, .evenings, [.cable]),
        // Kaunas (8)
        ("pk01", "Žaliakalnis", "Kovo 11-osios g. 47", "Kaunas", 54.9067, 23.9375, .homeowner, 11, 1, 0.31, .evenings, [.cable]),
        ("pk02", "Aleksotas", "Veiverių g. 66", "Kaunas", 54.8810, 23.9025, .homeowner, 7.4, 1, 0.29, .evenings, [.covered]),
        ("pk03", "Dainava", "Partizanų g. 104", "Kaunas", 54.8947, 23.9551, .homeowner, 11, 1, 0.30, .always, [.lit]),
        ("pk04", "Šilainiai", "Baltų pr. 19", "Kaunas", 54.9206, 23.8742, .homeowner, 7.4, 1, 0.28, .evenings, []),
        ("pk05", "Centras", "Laisvės al. 81", "Kaunas", 54.8984, 23.9153, .homeowner, 11, 1, 0.35, .always, [.cctv]),
        ("pk06", "Panemunė", "Vaidoto g. 24", "Kaunas", 54.8654, 23.9741, .homeowner, 11, 1, 0.31, .evenings, [.cable]),
        ("pk07", "Donelaičio g.", "K. Donelaičio g. 27", "Kaunas", 54.8996, 23.9206, .stationOwner, 22, 2, 0.41, .always, [.lit, .wc, .wifi]),
        ("pk08", "Savanorių pr.", "Savanorių pr. 287", "Kaunas", 54.9244, 23.9568, .stationOwner, 50, 2, 0.46, .workdays, [.covered, .cctv]),
        // Klaipėda (5)
        ("pl01", "Senamiestis", "Tiltų g. 12", "Klaipėda", 55.7085, 21.1324, .homeowner, 11, 1, 0.34, .always, [.lit]),
        ("pl02", "Melnragė", "Vėtros g. 7", "Klaipėda", 55.7286, 21.0981, .homeowner, 11, 1, 0.33, .evenings, [.cable]),
        ("pl03", "Debreceno g.", "Debreceno g. 41", "Klaipėda", 55.6767, 21.1712, .homeowner, 7.4, 1, 0.29, .evenings, [.covered]),
        ("pl04", "Giruliai", "Šlaito g. 3", "Klaipėda", 55.7596, 21.0928, .homeowner, 11, 1, 0.32, .evenings, []),
        ("pl05", "Minijos g.", "Minijos g. 180", "Klaipėda", 55.6835, 21.1532, .stationOwner, 22, 3, 0.40, .workdays, [.cctv, .wc]),
        // Šiauliai (3)
        ("ps01", "Centras", "Vilniaus g. 205", "Šiauliai", 55.9318, 23.3150, .homeowner, 11, 1, 0.30, .evenings, [.cable]),
        ("ps02", "Lieporiai", "Lieporių g. 9", "Šiauliai", 55.9161, 23.2776, .homeowner, 7.4, 1, 0.27, .evenings, []),
        ("ps03", "Tilžės g.", "Tilžės g. 72", "Šiauliai", 55.9241, 23.3082, .stationOwner, 22, 2, 0.38, .always, [.lit, .wifi]),
        // Panevėžys (2)
        ("pp01", "Ramygalos g.", "Ramygalos g. 48", "Panevėžys", 55.7254, 24.3768, .homeowner, 11, 1, 0.29, .evenings, [.cable]),
        ("pp02", "Klaipėdos g.", "Klaipėdos g. 99", "Panevėžys", 55.7389, 24.3388, .stationOwner, 22, 2, 0.37, .workdays, [.covered]),
        // Resorts (2)
        ("pd01", "Vytauto g.", "Vytauto g. 30", "Druskininkai", 54.0153, 23.9735, .stationOwner, 22, 2, 0.42, .always, [.lit, .wc, .wifi]),
        ("pg01", "Birutės al.", "Birutės al. 44", "Palanga", 55.9097, 21.0646, .homeowner, 11, 1, 0.38, .always, [.cable, .lit]),
    ]

    static let listings: [HostListing] = rows.map { r in
        var l = HostListing()
        l.id = "host-demo-\(r.id)"
        l.kind = r.kind
        l.title = r.kind == .homeowner ? tr("Home charger · \(r.area)") : tr("Business charger · \(r.area)")
        l.address = r.address
        l.city = r.city
        l.location = LatLng(lat: r.lat, lng: r.lng)
        l.connector = r.kw >= 50 ? .ccs2 : .type2
        l.powerKw = r.kw
        l.spots = r.spots
        l.pricePerKwh = r.price
        l.schedule = r.schedule
        l.amenities = r.amenities
        l.instantBook = r.kind == .homeowner ? (Int(String(r.id.suffix(1))) ?? 0) % 2 == 0 : true
        return l
    }

    /// The listings as map stations at `date`. Closed ones are left out; some
    /// open ones are in use, varying by hour so the map doesn't look all-free.
    static func stations(at date: Date = .now, calendar: Calendar = .current) -> [Station] {
        let hour = calendar.component(.hour, from: date)
        return listings.enumerated().compactMap { i, listing in
            guard var s = Hosting.station(for: listing, at: date) else { return nil }
            for c in s.connectors.indices where (i * 7 + c * 3 + hour) % 5 == 0 {
                s.connectors[c].status = .charging
            }
            return s
        }
    }
}
