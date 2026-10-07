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
                Text("Kaip efektyviau išnaudoti jau esamą įkrovimo infrastruktūrą. Demonstraciniai duomenys.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
                filters
                if filtered.isEmpty {
                    EmptyStateCard(title: "Nėra stotelių", message: "Pakeiskite filtrus.", systemImage: "line.3.horizontal.decrease.circle")
                } else {
                    let sum = Analytics.summary(filtered, idleReduction: reduction)
                    kpis(sum)
                    SectionHeader(title: "Poveikio modelis")
                    impact(sum)
                    SectionHeader(title: "Paklausa pagal valandas")
                    CardBox {
                        OccupancyChart(values: sum.hourlyDemand, currentHour: Calendar.current.component(.hour, from: .now))
                    }
                    SectionHeader(title: "Daugiausia prarasto laiko")
                    stationList(sum)
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Operatoriams")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filters: some View {
        HStack {
            Picker("Miestas", selection: $city) {
                Text("Visi miestai").tag("")
                ForEach(cities, id: \.self) { Text($0).tag($0) }
            }
            Picker("Operatorius", selection: $operatorId) {
                Text("Visi operatoriai").tag("")
                ForEach(DemoData.operators) { Text($0.name).tag($0.id) }
            }
        }
        .pickerStyle(.menu)
        .padding(.bottom, 12)
    }

    private func kpis(_ sum: NetworkSummary) -> some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                CardBox { StatView(label: "Įkrovimų per dieną", value: "\(sum.sessionsPerDay)", sub: "\(filtered.count) stotelės") }
                CardBox { StatView(label: "Vid. „idle“ laikas", value: Fmt.minutes(sum.avgIdleMin), sub: "\(Int(sum.idleHoursPerDay)) val. per dieną") }
            }
            GridRow {
                CardBox { StatView(label: "Piktnaudžiavimo atvejai", value: "\(sum.abuseCases7d)", sub: "per 7 dienas") }
                CardBox(stroke: Theme.brand) { StatView(label: "Papildomai aptarnautų vairuotojų", value: "+\(sum.extraSessionsPerDay)/d.", sub: "be naujų stotelių") }
            }
        }
    }

    private func impact(_ sum: NetworkSummary) -> some View {
        CardBox {
            Text("„Idle“ laiko sumažėjimas dėl grace period, mokesčio ir taškų: **\(Fmt.pct(reduction))**")
                .font(.subheadline)
            Slider(value: $reduction, in: 0.1...0.9, step: 0.05)
            Chart {
                BarMark(x: .value("Min.", sum.avgIdleMin), y: .value("", "Dabar"))
                    .foregroundStyle(Theme.bad)
                    .annotation(position: .trailing) { Text(Fmt.minutes(sum.avgIdleMin)).font(.caption.bold()) }
                BarMark(x: .value("Min.", sum.avgIdleMinAfter), y: .value("", "Su Unplugged"))
                    .foregroundStyle(Theme.ok)
                    .annotation(position: .trailing) { Text(Fmt.minutes(sum.avgIdleMinAfter)).font(.caption.bold()) }
            }
            .chartXAxis(.hidden)
            .chartXScale(domain: 0...(sum.avgIdleMin * 1.3))
            .frame(height: 100)
            .padding(.top, 8)
            Text("Atlaisvinama \(Int(sum.idleHoursSavedPerDay)) val. stotelių laiko per dieną → ~\(sum.extraSessionsPerDay) papildomų įkrovimų iš to paties stotelių skaičiaus.")
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
                        StatView(label: "Užimtumas", value: Fmt.pct(st.utilization))
                        StatView(label: "Įkrovimai/d.", value: "\(st.sessionsPerDay)")
                        StatView(label: "Vid. idle", value: "\(st.avgIdleMin) min.", sub: Fmt.pct(st.idleShare))
                        StatView(label: "Pažeid. 7 d.", value: "\(st.abuseCases7d)")
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
}
