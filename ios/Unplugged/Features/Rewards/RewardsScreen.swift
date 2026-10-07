import SwiftUI

struct RewardsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Atsakingai naudodamiesi stotelėmis renkate taškus ir keičiate juos į nuolaidas.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 12)
                    balance
                    SectionHeader(title: "Kaip uždirbti")
                    CardBox {
                        ForEach(Array(PointsReason.earning.enumerated()), id: \.element) { item in
                            if item.offset > 0 { Divider().padding(.vertical, 8) }
                            HStack {
                                Text(item.element.label).font(.subheadline)
                                Spacer()
                                Text("+\(item.element.points)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ok)
                            }
                        }
                    }
                    SectionHeader(title: "Iškeisti")
                    VStack(spacing: 8) {
                        ForEach(Points.rewards) { reward in rewardRow(reward) }
                    }
                    SectionHeader(title: "Istorija")
                    history
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Taškai")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Atstatyti demo duomenis", role: .destructive) { confirmReset = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Atstatyti visus demo duomenis?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Atstatyti", role: .destructive) { model.resetDemo() }
            }
        }
    }

    private var balance: some View {
        let tier = Points.tier(for: model.lifetimePoints)
        return CardBox {
            Text("Jūsų taškai").font(.subheadline).foregroundStyle(.secondary)
            Text("\(model.points)")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            HStack {
                Text(tier.current.name).font(.subheadline.weight(.semibold))
                Spacer()
                if let next = tier.next {
                    Text("iki „\(next.name)“ liko \(next.min - model.lifetimePoints)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
            if let next = tier.next {
                let progress = Double(model.lifetimePoints - tier.current.min) / Double(next.min - tier.current.min)
                SocBar(value: progress * 100, height: 8).padding(.top, 4)
            }
        }
    }

    private func rewardRow(_ reward: Points.Reward) -> some View {
        let affordable = model.points >= reward.cost
        return CardBox {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reward.title).font(.headline)
                    Text(reward.partner).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("\(reward.cost) tšk.") { model.redeem(reward) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!affordable)
            }
        }
    }

    private var history: some View {
        CardBox {
            if model.history.isEmpty {
                Text("Kol kas nieko.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(model.history.prefix(20).enumerated()), id: \.element.id) { item in
                let h = item.element
                if item.offset > 0 { Divider().padding(.vertical, 8) }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.reason == .redeem ? (h.note ?? h.reason.label) : h.reason.label).font(.subheadline)
                        Text([h.at.formatted(date: .abbreviated, time: .omitted), h.reason == .redeem ? nil : h.note].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(h.points > 0 ? "+\(h.points)" : "\(h.points)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(h.points > 0 ? Theme.ok : Color.primary)
                }
            }
        }
    }
}
