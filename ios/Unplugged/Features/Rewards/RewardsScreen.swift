import SwiftUI

struct RewardsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var selectedReward: Points.Reward?
    @State private var requestId = UUID().uuidString

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                Text("Earn points in the demo and exchange them for simulated rewards. No real credits or partner benefits are activated.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .padding(.bottom, 12)
                balance
                SectionHeader(title: "How to earn")
                CardBox {
                    ForEach(Array(PointsReason.earning.filter { $0 != .offPeak }.enumerated()), id: \.element) { item in
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
                SectionHeader(title: "Simulated rewards")
                redemptionRecords
                SectionHeader(title: "History")
                history
            }
            .padding(16)
        }
        .tabBarClearance()
        .screenBackdrop()
        .confirmationDialog("Redeem demo reward?", isPresented: Binding(
            get: { selectedReward != nil }, set: { if !$0 { selectedReward = nil } }
        ), titleVisibility: .visible) {
            if let reward = selectedReward {
                Button("Redeem \(reward.cost) pts") {
                    model.redeem(reward, requestId: requestId)
                    selectedReward = nil
                }
            }
            Button("Cancel", role: .cancel) { selectedReward = nil }
        } message: {
            Text("This creates a simulated reward record. No partner benefit is activated.")
        }
        .navigationTitle("Points")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var balance: some View {
        let tier = Points.tier(for: model.lifetimePoints)
        return CardBox {
            Text("Your points").font(.subheadline).foregroundStyle(Theme.muted)
            Text("\(model.points)")
                .scaledFont(52, weight: .bold, design: .rounded, relativeTo: .largeTitle)
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
                Button("\(reward.cost) pts") {
                    requestId = UUID().uuidString
                    selectedReward = reward
                }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                    .foregroundStyle(Theme.ink)
                    .disabled(!affordable)
            }
        }
    }

    private var redemptionRecords: some View {
        CardBox {
            if model.rewardRedemptions.isEmpty {
                Text("No simulated rewards yet.").font(.caption).foregroundStyle(Theme.muted)
            }
            ForEach(model.rewardRedemptions) { record in
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title).font(.headline)
                    Text("Demo reward ID: \(record.id)").font(.caption2).foregroundStyle(Theme.muted)
                    Text("\(record.cost) pts").font(.caption)
                }.padding(.vertical, 6)
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
                        Text(h.reason == .redeem ? (h.redemptionId.flatMap { id in model.rewardRedemptions.first { $0.id == id }?.title } ?? trKey(h.note ?? h.reason.label)) : h.reason.label).font(.subheadline)
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
