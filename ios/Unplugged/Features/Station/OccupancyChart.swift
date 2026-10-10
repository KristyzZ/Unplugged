import Charts
import SwiftUI

/// 24-hour "usually busy" bar chart from historical occupancy.
///
/// Hours are plotted as numbers, not as 24 text categories: with categories
/// every label had to fit inside its own narrow bar slot and was cut to "…".
struct OccupancyChart: View {
    let values: [Double]
    let currentHour: Int
    var highlight: Int? = nil

    private func color(_ h: Int, _ v: Double) -> Color {
        if h == currentHour { return Theme.brand }
        if h == highlight { return Theme.ok }
        if v > 0.75 { return Theme.bad.opacity(0.55) }
        return Color.gray.opacity(0.35)
    }

    private struct Bar: Identifiable {
        let id: Int
        let start: Double
        let end: Double
        let height: Double
        let color: Color
    }

    private var bars: [Bar] {
        values.enumerated().map { hour, value in
            Bar(id: hour, start: Double(hour) - 0.36, end: Double(hour) + 0.36,
                height: max(0.03, value), color: color(hour, value))
        }
    }

    /// 24 finite values in 0...1, one per hour. Real stations have no history until #37 provides it.
    private var hasHistory: Bool {
        values.count == 24 && values.allSatisfy { $0.isFinite && (0...1).contains($0) }
    }

    var body: some View {
        if hasHistory { chart } else { noHistory }
    }

    private var noHistory: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis").font(.title2).foregroundStyle(Theme.muted)
            Text("Not enough data yet").font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
            Text("Busy-hour history is still being collected for this station.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .accessibilityElement(children: .combine)
    }

    private var chart: some View {
        Chart(bars) { bar in
            // Rectangles with explicit hour edges: on a numeric axis a bar
            // width ratio has no band to scale against and draws nothing.
            RectangleMark(
                xStart: .value("Hour", bar.start),
                xEnd: .value("Hour", bar.end),
                yStart: .value("Occupancy", 0.0),
                yEnd: .value("Occupancy", bar.height)
            )
            .foregroundStyle(bar.color)
            .cornerRadius(2)
        }
        .chartYScale(domain: 0...1)
        .chartYAxis(.hidden)
        .chartXScale(domain: -0.5...23.5)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18]) { value in
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text(String(format: "%02d:00", hour))
                    }
                }
                .foregroundStyle(Theme.muted)
            }
        }
        .frame(height: 120)
        .accessibilityLabel(Text("Usual occupancy by hour"))
    }
}
