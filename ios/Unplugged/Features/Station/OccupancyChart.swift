import Charts
import SwiftUI

/// 24-hour "usually busy" bar chart from historical occupancy.
struct OccupancyChart: View {
    let values: [Double]
    let currentHour: Int
    var highlight: Int? = nil

    private func label(_ h: Int) -> String { String(format: "%02d", h) }

    private func color(_ h: Int, _ v: Double) -> Color {
        if h == currentHour { return Theme.brand }
        if h == highlight { return Theme.ok }
        if v > 0.75 { return Theme.bad.opacity(0.55) }
        return Color.gray.opacity(0.35)
    }

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { item in
                BarMark(
                    x: .value("Valanda", label(item.offset)),
                    y: .value("Užimtumas", max(0.03, item.element))
                )
                .foregroundStyle(color(item.offset, item.element))
                .cornerRadius(2)
            }
        }
        .chartYScale(domain: 0...1)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: ["00", "06", "12", "18", "23"])
        }
        .frame(height: 120)
    }
}
