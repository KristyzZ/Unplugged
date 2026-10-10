import Foundation

/// The charging networks in the open Via Lietuva feed, by their OCPI `party_id`.
/// Ids of the networks our fictional demo plans and tests refer to keep their original
/// ids (`ignitis`, `inbalance`, `enefit`, `eleport`) so plan discounts keep working.
enum OperatorCatalog {
    private struct Entry {
        let partyId: String
        let id: String
        let name: String
        let colorHex: String
    }

    /// Ordered by network size (number of chargers).
    private static let entries: [Entry] = [
        Entry(partyId: "IBG", id: "inbalance", name: "Inbalance grid", colorHex: "2563EB"),
        Entry(partyId: "IGN", id: "ignitis", name: "Ignitis ON", colorHex: "0F766E"),
        Entry(partyId: "STR", id: "stuart", name: "Stuart Energy", colorHex: "0891B2"),
        Entry(partyId: "ELD", id: "eldrive", name: "Eldrive", colorHex: "16A34A"),
        Entry(partyId: "E85", id: "enefit", name: "Enefit Volt", colorHex: "EA580C"),
        Entry(partyId: "ETR", id: "elektrum", name: "Elektrum Drive", colorHex: "CA8A04"),
        Entry(partyId: "IKR", id: "ikrautas", name: "Įkrautas", colorHex: "DB2777"),
        Entry(partyId: "LLT", id: "lidl", name: "Lidl", colorHex: "1D4ED8"),
        Entry(partyId: "EVI", id: "evinfra", name: "EV Infrastruktūra", colorHex: "9333EA"),
        Entry(partyId: "008", id: "eleport", name: "Eleport", colorHex: "7C3AED"),
        Entry(partyId: "ION", id: "ionity", name: "IONITY", colorHex: "0EA5E9"),
        Entry(partyId: "NL1", id: "neste", name: "Neste", colorHex: "65A30D"),
        Entry(partyId: "SET", id: "virsi", name: "VIRŠI", colorHex: "DC2626"),
    ]

    static let all: [ChargeOperator] = entries.map { ChargeOperator(id: $0.id, name: $0.name, colorHex: $0.colorHex) }

    private static let byPartyId = Dictionary(uniqueKeysWithValues: entries.map { ($0.partyId, $0.id) })

    /// The app's operator id for an OCPI party id. An unknown network gets a lower-cased id of its own.
    static func operatorId(partyId: String) -> String {
        byPartyId[partyId.trimmingCharacters(in: .whitespaces).uppercased()] ?? partyId.lowercased()
    }

    static func chargeOperator(id: String) -> ChargeOperator? {
        all.first { $0.id == id }
    }
}
