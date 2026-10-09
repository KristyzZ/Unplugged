import SwiftUI

struct RewardsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false
    @State private var showOperator = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Use stations responsibly to earn points and exchange them for discounts.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .padding(.bottom, 12)
                    balance
                    SectionHeader(title: "How to earn")
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
                    SectionHeader(title: "Redeem")
                    VStack(spacing: 8) {
                        ForEach(Points.rewards) { reward in rewardRow(reward) }
                    }
                    SectionHeader(title: "History")
                    history
                }
                .padding(16)
            }
            .tabBarClearance()
            .background(Theme.background)
            .navigationTitle("Points")
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                ScreenHeader(title: "Points") {
                    Menu {
                        Button {
                            showOperator = true
                        } label: {
                            Label("For operators", systemImage: "chart.bar.xaxis")
                        }
                        LanguageMenu()
                        Button("Reset demo data", role: .destructive) { confirmReset = true }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 44, height: 44)
                            .glass(in: Circle())
                    }
                    .accessibilityLabel(Text("More"))
                }
            }
            .navigationDestination(isPresented: $showOperator) { OperatorScreen() }
            .confirmationDialog("Reset all demo data?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { model.resetDemo() }
            }
        }
    }

    private var balance: some View {
        let tier = Points.tier(for: model.lifetimePoints)
        return CardBox {
            Text("Your points").font(.subheadline).foregroundStyle(Theme.muted)
            Text("\(model.points)")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            HStack {
                Text(tier.current.name).font(.subheadline.weight(.semibold))
                Spacer()
                if let next = tier.next {
                    Text("Until “\(next.name)”: \(next.min - model.lifetimePoints) to go")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
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
                    Text(reward.partner).font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("\(reward.cost) pts") { model.redeem(reward) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                    .foregroundStyle(Theme.ink)
                    .disabled(!affordable)
            }
        }
    }

    private var history: some View {
        CardBox {
            if model.history.isEmpty {
                Text("Nothing yet.").font(.subheadline).foregroundStyle(Theme.muted)
            }
            ForEach(Array(model.history.prefix(20).enumerated()), id: \.element.id) { item in
                let h = item.element
                if item.offset > 0 { Divider().padding(.vertical, 8) }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.reason == .redeem ? (h.note ?? h.reason.label) : h.reason.label).font(.subheadline)
                        Text([h.at.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(L10n.locale)), h.reason == .redeem ? nil : h.note].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
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
