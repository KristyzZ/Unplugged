import Charts
import SwiftUI
import UIKit

/// Your car: what it is, how far it goes, how fast it charges.
struct CarScreen: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false

    var body: some View {
        let vehicle = model.vehicle
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(vehicle)
                battery(vehicle)
                specs(vehicle)
                if vehicle.dcKw > 0 {
                    ChargingCurveCard(vehicle: vehicle, soc: model.soc)
                }
                Text("Car data: \(VehicleCatalog.attribution)")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted.opacity(0.8))
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .tabBarClearance()
        .screenBackdrop()
        .navigationTitle("Car")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $picking) { VehiclePicker() }
    }

    private func header(_ v: Vehicle) -> some View {
        CardBox {
            HStack(spacing: 14) {
                IconBadge(systemImage: "car.side.fill").scaleEffect(1.3).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(v.brand).font(.subheadline).foregroundStyle(Theme.muted)
                    Text(v.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle(v)).font(.subheadline).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            Button("Change car") { picking = true }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, 14)
        }
    }

    private func subtitle(_ v: Vehicle) -> String {
        let battery = tr("\(Int(v.batteryKwh.rounded())) kWh usable")
        return [v.year.map(String.init), battery].compactMap { $0 }.joined(separator: " · ")
    }

    private func battery(_ v: Vehicle) -> some View {
        let socBinding = Binding(get: { model.soc }, set: { model.setSoc($0) })
        return CardBox {
            HStack(alignment: .firstTextBaseline) {
                Text("Battery now").font(.subheadline).foregroundStyle(Theme.muted)
                Spacer()
                Text("\(Int(model.soc)) %")
                    .scaledFont(22, weight: .bold, design: .rounded, relativeTo: .title2)
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
            }
            Slider(value: socBinding, in: 1...100, step: 1).tint(Theme.brand)
            ChargeLimitPicker()
                .padding(.top, 14)
            StatRow {
                StatView(label: "Range now", value: Fmt.km(v.rangeKm(soc: model.soc)))
                StatView(label: "At 80 %", value: Fmt.km(v.rangeKm(soc: 80)))
                StatView(label: "Full", value: Fmt.km(v.rangeKm(soc: 100)))
            }
            .padding(.top, 8)
        }
    }

    private func specs(_ v: Vehicle) -> some View {
        let ac = v.acPhases.map { tr("\(Fmt.kw(v.acKw)) · \($0)-phase") } ?? Fmt.kw(v.acKw)
        return ListCard {
            SpecRow(systemImage: "bolt.fill", title: "Fast charging (DC)", value: v.dcKw > 0 ? Fmt.kw(v.dcKw) : tr("Not supported"))
            RowDivider()
            SpecRow(systemImage: "powerplug.fill", title: "AC charging", value: ac)
            RowDivider()
            SpecRow(systemImage: "ev.plug.dc.ccs2", fallback: "cable.connector", title: "Plugs", value: v.connectors.map(\.label).joined(separator: ", "))
            RowDivider()
            SpecRow(systemImage: "gauge.with.dots.needle.33percent", title: "Consumption", value: String(format: "%.1f kWh/100 km", v.consumptionKwhPer100))
        }
    }
}

/// Icon, label and a value on the right; nothing to tap.
private struct SpecRow: View {
    let systemImage: String
    var fallback: String? = nil
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        ListRow(systemImage: symbol, title: title) {
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
        }
    }

    /// Newer SF Symbols aren't on every iOS version.
    private var symbol: String {
        guard let fallback, UIImage(systemName: systemImage) == nil else { return systemImage }
        return fallback
    }
}

// MARK: - Charging curve

/// How fast the car charges at each battery level — the reason 10→80 % is
/// quick and 80→100 % is slow.
private struct ChargingCurveCard: View {
    let vehicle: Vehicle
    let soc: Double

    private struct Point: Identifiable {
        let pct: Double
        let kw: Double
        var id: Double { pct }
    }

    private var points: [Point] {
        stride(from: 0.0, through: 100.0, by: 2.5).map { Point(pct: $0, kw: vehicle.dcPower(atSoc: $0)) }
    }

    /// 10 → 80 % on a charger that never holds the car back.
    private var tenToEighty: Int {
        let fast = Connector(id: "", type: .ccs2, powerKw: 400, status: .available)
        return Charging.chargeTime(vehicle, fast, from: 10, to: 80).minutes
    }

    var body: some View {
        CardBox {
            HStack {
                Text("Fast-charging speed").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Pill(text: vehicle.curveMeasured == true ? "Measured" : "Typical", color: Theme.muted)
            }

            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("Battery", p.pct), y: .value("kW", p.kw))
                        .foregroundStyle(LinearGradient(
                            colors: [Theme.brand.opacity(0.45), Theme.brand.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Battery", p.pct), y: .value("kW", p.kw))
                        .foregroundStyle(Theme.brand)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                RuleMark(x: .value("Battery", soc))
                    .foregroundStyle(Theme.text.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center) {
                        Text("now").font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
                    }
            }
            .chartXScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: [0, 20, 40, 60, 80, 100]) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel {
                        if let pct = value.as(Double.self) { Text("\(Int(pct)) %") }
                    }
                    .foregroundStyle(Theme.muted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel {
                        if let kw = value.as(Double.self) { Text("\(Int(kw))") }
                    }
                    .foregroundStyle(Theme.muted)
                }
            }
            .frame(height: 170)
            .padding(.top, 10)
            .accessibilityLabel(Text("Charging speed: up to \(Int(vehicle.dcKw)) kW"))

            Text("kW by battery level. 10 → 80 % takes about \(Fmt.minutes(Double(tenToEighty))) on a fast charger.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .padding(.top, 6)
        }
    }
}

// MARK: - Picker

/// Choose a car: search, or browse brand → model.
struct VehiclePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        VehicleRow(vehicle: model.vehicle, selected: true, showBrand: true)
                    } header: {
                        Text("Your car")
                    }
                    Section {
                        ForEach(VehicleCatalog.brands, id: \.name) { brand in
                            NavigationLink(value: brand.name) {
                                HStack {
                                    Text(brand.name).foregroundStyle(Theme.text)
                                    Spacer()
                                    Text("\(brand.count)").foregroundStyle(Theme.muted).monospacedDigit()
                                }
                            }
                            .listRowBackground(Theme.card)
                        }
                    } header: {
                        Text("Brands")
                    }
                } else {
                    let results = VehicleCatalog.search(query)
                    if results.isEmpty {
                        Text("No cars match “\(query)”.")
                            .foregroundStyle(Theme.muted)
                            .listRowBackground(Theme.card)
                    }
                    ForEach(results) { v in
                        Button { pick(v) } label: {
                            VehicleRow(vehicle: v, selected: v.id == model.vehicle.id, showBrand: true)
                        }
                        .listRowBackground(Theme.card)
                    }
                }
                Section {
                } footer: {
                    Text("\(VehicleCatalog.all.count) models. Car data: \(VehicleCatalog.attribution)")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Choose your car")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Brand, model or year"))
            .navigationDestination(for: String.self) { brand in
                BrandModels(brand: brand, selectedId: model.vehicle.id, onPick: pick)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(Theme.brand)
    }

    private func pick(_ v: Vehicle) {
        model.setVehicle(v.id)
        dismiss()
    }
}

/// One brand's cars, grouped by model, newest first.
private struct BrandModels: View {
    let brand: String
    let selectedId: String
    let onPick: (Vehicle) -> Void

    var body: some View {
        let groups = grouped(VehicleCatalog.vehicles(brand: brand))
        List {
            ForEach(groups, id: \.model) { group in
                Section {
                    ForEach(group.vehicles) { v in
                        Button { onPick(v) } label: {
                            VehicleRow(vehicle: v, selected: v.id == selectedId, showBrand: false)
                        }
                        .listRowBackground(Theme.card)
                    }
                } header: {
                    Text(group.model)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(brand)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func grouped(_ vehicles: [Vehicle]) -> [(model: String, vehicles: [Vehicle])] {
        var order: [String] = []
        var byModel: [String: [Vehicle]] = [:]
        for v in vehicles {
            if byModel[v.model] == nil { order.append(v.model) }
            byModel[v.model, default: []].append(v)
        }
        return order.map { ($0, byModel[$0]!.sorted { ($0.year ?? 0) > ($1.year ?? 0) }) }
    }
}

private struct VehicleRow: View {
    let vehicle: Vehicle
    let selected: Bool
    let showBrand: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.text)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            if selected {
                Image(systemName: "checkmark").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.brand)
            }
        }
        .contentShape(Rectangle())
        .listRowBackground(Theme.card)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var title: String {
        if showBrand { return vehicle.name }
        return vehicle.variant.isEmpty ? vehicle.model : vehicle.variant
    }

    private var details: String {
        var parts: [String] = []
        if let year = vehicle.year { parts.append(String(year)) }
        parts.append("\(Int(vehicle.batteryKwh.rounded())) kWh")
        if vehicle.dcKw > 0 { parts.append(tr("\(Fmt.kw(vehicle.dcKw)) DC")) }
        parts.append(tr("≈ \(Int(vehicle.rangeKm(soc: 100).rounded())) km"))
        return parts.joined(separator: " · ")
    }
}

/// "Usually charge to": the default target for new charges and trip stops.
struct ChargeLimitPicker: View {
    @Environment(AppModel.self) private var model
    private let options: [Double] = [70, 80, 90, 100]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usually charge to").font(.subheadline).foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { value in
                    Chip(title: "\(Int(value)) %", active: model.chargeLimit == value) { model.setChargeLimit(value) }
                }
            }
            Text("80 % is kinder to the battery and faster: the last 20 % charges slowly.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }
}
