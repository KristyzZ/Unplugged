import SwiftUI

/// The same net charging lines and frozen contract are used before and after start.
struct PricingBreakdownView: View {
    let terms: Pricing.Terms
    let charges: Pricing.Breakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Demo contract: \(terms.plan?.name ?? tr("Public tariff"))")
                .font(.subheadline.weight(.medium))
            Text("Demo billing: \(terms.tariff.operatorName). No real payment is collected.")
                .font(.caption).foregroundStyle(Theme.muted)
            switch terms.selection {
            case .accountPricingUnsupported:
                Text("Public tariff used. Account pricing is not supported for this station.")
                    .font(.caption).foregroundStyle(Theme.muted)
            case .planNotApplicable:
                Text("Public tariff used. Your plan does not apply to this connector.")
                    .font(.caption).foregroundStyle(Theme.muted)
            case .publicTariff, .operatorPlan:
                EmptyView()
            }
            line("Energy charge", charges.energy)
            line("Session start fee", charges.sessionStart)
            line("Charging time fee", charges.chargingTime)
            if charges.savings > 0 {
                HStack {
                    Text("Plan saving (already included)")
                    Spacer()
                    Text(Fmt.eur(charges.savings))
                }.font(.caption).foregroundStyle(Theme.ok)
            }
            Text("Charging terms are fixed when the session starts. Idle fees are separate and are not discounted.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
    }

    private func line(_ label: String, _ amount: Double) -> some View {
        HStack {
            Text(trKey(label)).foregroundStyle(Theme.muted)
            Spacer()
            Text(Fmt.eur(amount))
        }.font(.subheadline)
    }
}
