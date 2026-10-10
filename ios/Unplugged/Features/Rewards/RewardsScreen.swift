import SwiftUI

/// Points: what you have, what you can get for them, how to earn more.
struct RewardsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                balance
                section("Leaderboard") { LeaderboardCard() }
                section("Spend points") { rewards }
                section("How to earn") { earning }
                if !model.history.isEmpty {
                    section("History") { history }
                }
            }
            .padding(16)
        }
        .tabBarClearance()
        .screenBackdrop()
        .navigationTitle("Points")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A collapsed section; tapping the title shows its content.
    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) -> some View {
        CollapsibleSection(title: title, content: content)
    }

    // MARK: Balance

    private var balance: some View {
        let tier = Points.tier(for: model.lifetimePoints)
        return CardBox {
            HStack(alignment: .firstTextBaseline) {
                Text("\(model.points)")
                    .scaledFont(48, weight: .bold, design: .rounded, relativeTo: .largeTitle)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.text)
                Text("points").font(.headline).foregroundStyle(Theme.muted)
                Spacer()
                Pill(text: tier.current.name, color: Theme.warn)
            }
            if let next = tier.next {
                let progress = Double(model.lifetimePoints - tier.current.min) / Double(next.min - tier.current.min)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.fill)
                        Capsule().fill(Theme.brand).frame(width: geo.size.width * min(1, max(0, progress)))
                    }
                }
                .frame(height: 6)
                .padding(.top, 6)
                Text(tr("\(next.min - model.lifetimePoints) more to reach \(next.name)"))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 6)
            }
        }
    }

    // MARK: Rewards

    private var rewards: some View {
        ListCard {
            ForEach(Array(Points.rewards.enumerated()), id: \.element.id) { item in
                let reward = item.element
                let affordable = model.points >= reward.cost
                if item.offset > 0 { RowDivider() }
                HStack(spacing: 12) {
                    IconBadge(systemImage: "gift.fill", color: affordable ? Theme.brand : Theme.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reward.title).font(.body.weight(.medium)).foregroundStyle(Theme.text)
                        Text(reward.partner).font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button { model.redeem(reward) } label: {
                        Text("\(reward.cost)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(affordable ? Theme.ink : Theme.muted)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(affordable ? Theme.brand : Theme.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!affordable)
                    .accessibilityLabel(Text("Get for \(reward.cost) points"))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
        }
    }

    // MARK: Earning

    private var earning: some View {
        ListCard {
            ForEach(Array(PointsReason.earning.enumerated()), id: \.element) { item in
                if item.offset > 0 { RowDivider() }
                HStack(spacing: 12) {
                    IconBadge(systemImage: icon(item.element), color: Theme.ok)
                    Text(item.element.label).font(.subheadline).foregroundStyle(Theme.text)
                    Spacer()
                    Text("+\(item.element.points)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ok)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
        }
    }

    private func icon(_ reason: PointsReason) -> String {
        switch reason {
        case .movedFast: "hare.fill"
        case .movedInGrace: "car.side.fill"
        case .offPeak: "moon.fill"
        case .reportConfirmed: "checkmark.shield.fill"
        case .confirmReport: "hand.thumbsup.fill"
        case .handedOver: "arrow.left.arrow.right"
        case .redeem: "gift.fill"
        }
    }

    // MARK: History

    private var history: some View {
        ListCard {
            ForEach(Array(model.history.prefix(10).enumerated()), id: \.element.id) { item in
                let h = item.element
                if item.offset > 0 { RowDivider() }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.reason == .redeem ? (h.note ?? h.reason.label) : h.reason.label)
                            .font(.subheadline)
                            .foregroundStyle(Theme.text)
                        Text(h.at.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(L10n.locale)))
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(h.points > 0 ? "+\(h.points)" : "\(h.points)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(h.points > 0 ? Theme.ok : Theme.muted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
        }
    }
}

/// Section header that hides its content until tapped, styled like
/// "More information" on the station screen.
private struct CollapsibleSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded.animation(Motion.pick(.spring(duration: 0.3)))) {
            content().padding(.top, 8)
        } label: {
            Text(title).font(.headline).foregroundStyle(Theme.text).frame(minHeight: 44)
        }
        .tint(Theme.muted)
    }
}
