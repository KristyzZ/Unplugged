import SwiftUI

/// Compact community ranking: a Points / CO₂ switch, the top three and your
/// own place, with the full list one tap away. Shown inside the Points
/// screen's collapsible "Leaderboard" section.
struct LeaderboardCard: View {
    @Environment(AppModel.self) private var model
    @State private var metric: Leaderboard.Metric = .points
    @State private var expanded = false

    private var rows: [Leaderboard.Row] {
        let you = Leaderboard.Driver(id: "you", name: tr("You"), points: model.lifetimePoints,
                                     co2Kg: Leaderboard.co2Saved(model.sessionHistory), isYou: true)
        return Leaderboard.ranked(Leaderboard.demoDrivers + [you], by: metric)
    }

    var body: some View {
        let all = rows
        let compact = Leaderboard.compact(all)
        VStack(alignment: .leading, spacing: 8) {
            // The "Leaderboard" title is the collapsible section header on the Points screen.
            Picker("Rank by", selection: $metric) {
                Text("Points").tag(Leaderboard.Metric.points)
                Text("CO₂ saved").tag(Leaderboard.Metric.co2)
            }
            .pickerStyle(.segmented)
            ListCard {
                let shown = expanded ? all : compact.top
                ForEach(Array(shown.enumerated()), id: \.element.id) { item in
                    if item.offset > 0 { RowDivider() }
                    row(item.element)
                }
                if !expanded, let you = compact.you {
                    RowDivider()
                    row(you)
                }
                RowDivider()
                Button {
                    withMotion(.spring(duration: 0.3)) { expanded.toggle() }
                } label: {
                    Text(expanded ? "Show less" : "Show all \(all.count)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.brand)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text(metric == .co2
                 ? "Estimated vs. a petrol car, from the energy you charged. Other drivers are demo data."
                 : "Lifetime points. Other drivers are demo data.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }

    private func row(_ r: Leaderboard.Row) -> some View {
        let you = r.driver.isYou
        return HStack(spacing: 12) {
            rankBadge(r.rank)
            Text(r.driver.name)
                .font(.subheadline.weight(you ? .semibold : .regular))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer()
            Text(valueText(r.driver))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(you ? Theme.brand : Theme.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(you ? Theme.brand.opacity(0.10) : .clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(tr("Place \(r.rank): \(r.driver.name), \(valueText(r.driver))")))
    }

    private func rankBadge(_ rank: Int) -> some View {
        let medal: Color? = switch rank {
        case 1: Color(red: 0.98, green: 0.78, blue: 0.25)
        case 2: Color(red: 0.78, green: 0.80, blue: 0.84)
        case 3: Color(red: 0.85, green: 0.55, blue: 0.32)
        default: nil
        }
        return Text("\(rank)")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(medal == nil ? Theme.muted : Theme.ink)
            .frame(width: 26, height: 26)
            .background(medal ?? Theme.fill, in: Circle())
    }

    private func valueText(_ d: Leaderboard.Driver) -> String {
        switch metric {
        case .points: tr("\(d.points) pts")
        case .co2: tr("\(Int(d.co2Kg.rounded())) kg")
        }
    }
}
