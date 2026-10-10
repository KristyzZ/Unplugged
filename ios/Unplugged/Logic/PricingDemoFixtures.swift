import Foundation

/// Fictional fixtures matching the existing Profile plan benefits. Not operator offers.
/// Kept outside Models/DemoData.swift so the provenance/data lanes can evolve models.
enum PricingDemoFixtures {
    static let plans: [Pricing.Plan] = [
        .init(id: "ignitis", operatorId: "ignitis", name: "Ignitis ON Plus", energyDiscount: 0.10),
        .init(id: "eleport", operatorId: "eleport", name: "Eleport Flex", waivesStartFee: true),
        .init(id: "enefit", operatorId: "enefit", name: "Enefit Volt Member", energyDiscount: 0.08),
        .init(id: "inbalance", operatorId: "inbalance", name: "Inbalance Pass", energyDiscount: 0.12, acOnly: true),
    ]

    static func tariff(station: Station, connector: Connector) -> Pricing.Tariff {
        // Explicit demo allowlist. An unfamiliar/imported station never gains
        // account pricing merely because its operator matches a profile toggle.
        let simulated = DemoData.seeds.contains { $0.id == station.id && $0.operatorId == station.operatorId }
        let start = simulated ? (station.operatorId == "eleport" ? 0.50 : 0.30) : 0
        let time = simulated ? (connector.type.isDC ? 0.02 : 0.01) : 0
        return Pricing.Tariff(id: "demo:\(station.id):\(connector.id)", operatorId: station.operatorId,
                              operatorName: DemoData.chargeOperator(station.operatorId).name,
                              energyEurPerKwh: station.pricePerKwh, startEur: start,
                              chargingEurPerMinute: time, supportsAccountPricing: simulated)
    }

    static func energyKwh(vehicle: Vehicle, from: Double, to: Double) -> Double {
        max(0, to - from) / 100 * vehicle.batteryKwh / 0.92
    }
}
