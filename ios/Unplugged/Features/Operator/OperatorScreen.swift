import Charts
import SwiftUI

/// Analytics for the city and charging operators (demo data).
struct OperatorScreen: View {
    @Environment(AppModel.self) private var model
    @State private var city = "Vilnius"
    @State private var operatorId = ""
    @State private var reduction = Analytics.defaultIdleReduction

    private var filtered: [Station] {
        model.stations.filter { (city.isEmpty || $0.city == city) && (operatorId.isEmpty || $0.operatorId == operatorId) }
    }

    private var cities: [String] {
        var seen: [String] = []
        for s in model.stations where !seen.contains(s.city) { seen.append(s.city) }
        return seen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("How to make better use of existing charging infrastructure. Demo data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
                filters
                if filtered.isEmpty {
                    EmptyStateCard(title: "No stations", message: "Change the filters.", systemImage: "line.3.horizontal.decrease.circle")
                } else {
                    let sum = Analytics.summary(filtered, idleReduction: reduction)
                    kpis(sum)
                    SectionHeader(title: "Impact model")
                    impact(sum)
                    SectionHeader(title: "Demand by hour")
                    CardBox {
                        OccupancyChart(values: sum.hourlyDemand, currentHour: Calendar.current.component(.hour, from: .now))
                    }
                    SectionHeader(title: "Most time lost")
                    stationList(sum)
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("For operators")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filters: some View {
        HStack {
            Picker("City", selection: $city) {
                Text("All cities").tag("")
                ForEach(cities, id: \.self) { Text($0).tag($0) }
            }
            Picker("Operator", selection: $operatorId) {
                Text("All operators").tag("")
                ForEach(DemoData.operators) { Text($0.name).tag($0.id) }
            }
        }
        .pickerStyle(.menu)
        .padding(.bottom, 12)
    }

    private func kpis(_ sum: NetworkSummary) -> some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                CardBox { StatView(label: "Sessions per day", value: "\(sum.sessionsPerDay)", sub: tr("\(filtered.count) stations")) }
                CardBox { StatView(label: "Avg. idle time", value: Fmt.minutes(sum.avgIdleMin), sub: tr("\(Int(sum.idleHoursPerDay)) h per day")) }
            }
            GridRow {
                CardBox { StatView(label: "Abuse cases", value: "\(sum.abuseCases7d)", sub: "in 7 days") }
                CardBox(stroke: Theme.brand) { StatView(label: "Additional drivers served", value: tr("+\(sum.extraSessionsPerDay)/day"), sub: "without new stations") }
            }
        }
    }

    private func impact(_ sum: NetworkSummary) -> some View {
        CardBox {
            Text("Idle time reduction from the grace period, fees and points: **\(Fmt.pct(reduction))**")
                .font(.subheadline)
            Slider(value: $reduction, in: 0.1...0.9, step: 0.05)
            Chart {
                BarMark(x: .value("Min.", sum.avgIdleMin), y: .value("", tr("Now")))
                    .foregroundStyle(Theme.bad)
                    .annotation(position: .trailing) { Text(Fmt.minutes(sum.avgIdleMin)).font(.caption.bold()) }
                BarMark(x: .value("Min.", sum.avgIdleMinAfter), y: .value("", tr("With Unplugged")))
                    .foregroundStyle(Theme.ok)
                    .annotation(position: .trailing) { Text(Fmt.minutes(sum.avgIdleMinAfter)).font(.caption.bold()) }
            }
            .chartXAxis(.hidden)
            .chartXScale(domain: 0...(sum.avgIdleMin * 1.3))
            .frame(height: 100)
            .padding(.top, 8)
            Text("Frees up \(Int(sum.idleHoursSavedPerDay)) station-hours per day → ~\(sum.extraSessionsPerDay) additional sessions from the same number of stations.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    private func stationList(_ sum: NetworkSummary) -> some View {
        let sorted = sum.stations.sorted {
            Double($0.avgIdleMin * $0.sessionsPerDay) > Double($1.avgIdleMin * $1.sessionsPerDay)
        }
        return VStack(spacing: 8) {
            ForEach(sorted) { st in
                CardBox {
                    HStack {
                        Text(st.station.name).font(.headline)
                        Spacer()
                        Text(DemoData.chargeOperator(st.station.operatorId).name).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .top) {
                        StatView(label: "Occupancy", value: Fmt.pct(st.utilization))
                        StatView(label: "Sessions/day", value: "\(st.sessionsPerDay)")
                        StatView(label: "Avg. idle", value: tr("\(st.avgIdleMin) min"), sub: Fmt.pct(st.idleShare))
                        StatView(label: "Offences 7 d", value: "\(st.abuseCases7d)")
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
}
