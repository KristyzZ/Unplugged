import Foundation

/// Pure EUR pricing shared by session estimates, receipts and future recommendations.
/// Idle fees are deliberately separate from charging charges and plan discounts.
enum Pricing {
    struct Tariff: Codable, Equatable {
        let id: String
        let operatorId: String
        let operatorName: String
        let energyEurPerKwh: Double
        let startEur: Double
        let chargingEurPerMinute: Double
        /// Must be explicitly confirmed by the data adapter; defaults to public pricing.
        var supportsAccountPricing = false
    }

    struct Plan: Codable, Equatable {
        let id: String
        let operatorId: String
        let name: String
        var energyDiscount: Double = 0
        var waivesStartFee = false
        var acOnly = false
    }

    enum Selection: String, Codable {
        case publicTariff, operatorPlan, accountPricingUnsupported, planNotApplicable
    }

    /// A value snapshot captured at start, independent of later profile or tariff changes.
    struct Terms: Codable, Equatable {
        let tariff: Tariff
        let plan: Plan?
        let selection: Selection

        var energyEurPerKwh: Double {
            tariff.energyEurPerKwh * (1 - min(1, max(0, plan?.energyDiscount ?? 0)))
        }
        var startEur: Double { plan?.waivesStartFee == true ? 0 : tariff.startEur }
    }

    struct Breakdown: Equatable {
        let energy: Double
        let sessionStart: Double
        let chargingTime: Double
        /// Difference from the same public tariff; already included in the net lines.
        let savings: Double
        var total: Double { Pricing.money(Pricing.decimal(energy) + Pricing.decimal(sessionStart) + Pricing.decimal(chargingTime)) }
    }

    struct Estimate: Equatable {
        let terms: Terms
        let charges: Breakdown
    }

    static func freeze(tariff: Tariff, plans: [Plan], activePlanIds: Set<String>, isAC: Bool) -> Terms {
        let selected = plans.filter { $0.operatorId == tariff.operatorId && activePlanIds.contains($0.id) }
        guard !selected.isEmpty else { return Terms(tariff: tariff, plan: nil, selection: .publicTariff) }
        guard tariff.supportsAccountPricing else {
            return Terms(tariff: tariff, plan: nil, selection: .accountPricingUnsupported)
        }
        guard let plan = selected.first(where: { !$0.acOnly || isAC }) else {
            return Terms(tariff: tariff, plan: nil, selection: .planNotApplicable)
        }
        return Terms(tariff: tariff, plan: plan, selection: .operatorPlan)
    }

    static func estimate(tariff: Tariff, plans: [Plan], activePlanIds: Set<String>, isAC: Bool,
                         kwh: Double, chargingMinutes: Double) -> Estimate {
        let terms = freeze(tariff: tariff, plans: plans, activePlanIds: activePlanIds, isAC: isAC)
        return Estimate(terms: terms, charges: charges(terms: terms, kwh: kwh, chargingMinutes: chargingMinutes))
    }

    static func charges(terms: Terms, kwh: Double, chargingMinutes: Double) -> Breakdown {
        let energy = decimal(kwh)
        let minutes = decimal(chargingMinutes)
        let discount = decimal(min(1, max(0, terms.plan?.energyDiscount ?? 0)))
        let publicEnergy = energy * decimal(terms.tariff.energyEurPerKwh)
        let netEnergy = money(publicEnergy * (1 - discount))
        let start = money(decimal(terms.startEur))
        let time = money(minutes * decimal(terms.tariff.chargingEurPerMinute))
        let saved = money(decimal(money(publicEnergy)) - decimal(netEnergy)
                          + decimal(money(decimal(terms.tariff.startEur))) - decimal(start))
        return Breakdown(energy: netEnergy, sessionStart: start, chargingTime: time, savings: saved)
    }

    /// Rates/quantities are nonnegative. Decimal arithmetic rounds each billed line
    /// once to cents, with ties away from zero, rather than rounding a binary product.
    private static func decimal(_ value: Double) -> Decimal {
        guard value.isFinite, value > 0 else { return 0 }
        return Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    private static func money(_ value: Decimal) -> Double {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 2, .plain)
        return NSDecimalNumber(decimal: output).doubleValue
    }
}
