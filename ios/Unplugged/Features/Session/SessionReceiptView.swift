import SwiftUI

extension SessionHistoryOrigin {
    var title: String {
        switch self {
        case .seededDemo: tr("Seeded demo session")
        case .simulatedDemo: tr("Simulated session")
        case .legacyDemo: tr("Legacy demo session")
        }
    }
}

struct SessionReceiptDetails: View {
    let session: ChargingSession
    var body: some View {
        let snap = SessionSnapshot(session, now: session.endedAt ?? session.scheduledDoneAt)
        VStack(alignment: .leading, spacing: 8) {
            Text("Receipt").font(.headline)
            Text(session.historyOrigin.title).font(.caption).foregroundStyle(Theme.muted)
            Text(session.stationName).font(.headline)
            Text(session.connectorLabel).font(.caption)
            Text("Receipt ID: \(session.id)").font(.caption2).foregroundStyle(Theme.muted)
                .textSelection(.enabled)
            line(tr("Energy"), String(format: "%.1f kWh", snap.kwh))
            if let terms = session.pricingTerms, let charges = snap.pricingCharges {
                PricingBreakdownView(terms: terms, charges: charges)
            } else {
                line(tr("Energy charge"), Fmt.eur(snap.chargingCost))
            }
            line(tr("Idle fee"), Fmt.eur(snap.idleFee))
            Divider()
            line(tr("Total"), Fmt.eur(snap.chargingCost + snap.idleFee))
            line(tr("Points earned"), "\(session.pointsEarned ?? 0)")
            Text("Simulated receipt. No payment was made.").font(.caption).foregroundStyle(Theme.muted)
        }
    }
    private func line(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value) }.font(.subheadline)
    }
}

struct SessionReceiptView: View {
    let session: ChargingSession
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView { CardBox { SessionReceiptDetails(session: session) }.padding(16) }
                .screenBackdrop().navigationTitle("Receipt")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
