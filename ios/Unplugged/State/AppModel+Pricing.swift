import Foundation

extension AppModel {
    func pricingTerms(at station: Station, connector: Connector) -> Pricing.Terms {
        Pricing.freeze(tariff: PricingDemoFixtures.tariff(station: station, connector: connector),
                       plans: PricingDemoFixtures.plans, activePlanIds: activePlanIds,
                       isAC: !connector.type.isDC)
    }

    func chargingEstimate(at station: Station, connector: Connector, targetSoc: Double) -> Pricing.Estimate {
        let duration = Charging.chargeTime(vehicle, connector, from: soc, to: targetSoc)
        let terms = pricingTerms(at: station, connector: connector)
        return Pricing.Estimate(terms: terms, charges: Pricing.charges(
            terms: terms, kwh: PricingDemoFixtures.energyKwh(vehicle: vehicle, from: soc, to: targetSoc),
            chargingMinutes: Double(max(1, duration.minutes))))
    }
}
