import SwiftUI

/// Vehicles, payment methods, operator plans and settings. The selected
/// vehicle drives range estimates, connector compatibility and trip planning.
struct ProfileScreen: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "My car").padding(.top, 0)
                    vehicleCard
                    SectionHeader(title: "Payment methods")
                    paymentCard
                    SectionHeader(title: "Subscriptions")
                    plansCard
                    SectionHeader(title: "Rewards")
                    pointsLink
                    SectionHeader(title: "For operators")
                    operatorLink
                    SectionHeader(title: "Settings")
                    settingsCard
                }
                .padding(16)
            }
            .tabBarClearance()
            .screenBackdrop()
            .navigationTitle("Profile")
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: "Profile") }
            .confirmationDialog("Reset all demo data?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { model.resetDemo() }
            }
        }
    }

    // MARK: Vehicle

    private var vehicleCard: some View {
        let vehicle = model.vehicle
        let vehicleBinding = Binding(get: { model.vehicleId }, set: { model.setVehicle($0) })
        let socBinding = Binding(get: { model.soc }, set: { model.setSoc($0) })
        return CardBox {
            Text("Car").font(.subheadline.weight(.medium))
            DropdownField(selection: vehicleBinding, options: DemoData.vehicles.map { ($0.id, $0.name) })
                .padding(.top, 4)
            Divider().padding(.vertical, 12)
            StatRow {
                StatView(label: "Battery", value: "\(Int(vehicle.batteryKwh)) kWh")
                StatView(label: "Max DC", value: "\(Int(vehicle.maxDcKw)) kW")
                StatView(label: "Max AC", value: "\(Int(vehicle.maxAcKw)) kW")
            }
            StatRow {
                StatView(label: "Consumption", value: String(format: "%.0f kWh/100 km", vehicle.consumptionKwhPer100))
                StatView(label: "Connectors", value: vehicle.connectors.map(\.rawValue).joined(separator: ", "))
            }
            .padding(.top, 10)
            Divider().padding(.vertical, 12)
            Text("Current battery level: \(Int(model.soc)) %").font(.subheadline.weight(.medium))
            Slider(value: socBinding, in: 1...100, step: 1)
            SocBar(value: model.soc)
            StatRow {
                StatView(label: "Range now", value: Fmt.km(vehicle.rangeKm(soc: model.soc)))
                StatView(label: "Range at 80 %", value: Fmt.km(vehicle.rangeKm(soc: 80)))
                StatView(label: "Range at 100 %", value: Fmt.km(vehicle.rangeKm(soc: 100)))
            }
            .padding(.top, 12)
            Text("Range is estimated from your car's battery size and real-world consumption. It is used for trip planning and for showing compatible chargers.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .padding(.top, 8)
        }
    }

    // MARK: Payments

    private var paymentCard: some View {
        CardBox {
            ForEach(Array(DemoData.paymentMethods.enumerated()), id: \.element.id) { item in
                let method = item.element
                if item.offset > 0 { Divider().padding(.vertical, 8) }
                Button { model.setDefaultPayment(method.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: method.systemImage).frame(width: 28).foregroundStyle(Theme.brand)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(method.title).font(.subheadline.weight(.medium))
                            Text(method.detail).font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if model.defaultPaymentId == method.id {
                            Pill(text: tr("Default"), color: Theme.ok)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("Demo payment methods. Payments are simulated in this prototype.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .padding(.top, 10)
        }
    }

    // MARK: Subscriptions

    private var plansCard: some View {
        CardBox {
            ForEach(Array(DemoData.plans.enumerated()), id: \.element.id) { item in
                let plan = item.element
                let binding = Binding(
                    get: { model.activePlanIds.contains(plan.id) },
                    set: { model.setPlan(plan.id, active: $0) }
                )
                if item.offset > 0 { Divider().padding(.vertical, 8) }
                Toggle(isOn: binding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.name).font(.subheadline.weight(.medium))
                        Text("\(DemoData.chargeOperator(plan.id).name) · \(plan.perk)")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.brand)
            }
            Text("Fictional demo plans. Linking real operator accounts needs operator-supported authorization.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .padding(.top, 10)
        }
    }

    // MARK: Points

    private var pointsLink: some View {
        NavigationLink {
            RewardsScreen()
        } label: {
            CardBox {
                HStack {
                    Image(systemName: "star.fill").foregroundStyle(Theme.warn)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Points").font(.subheadline.weight(.medium))
                        Text("\(model.points) pts · \(Points.tier(for: model.lifetimePoints).current.name)")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Operators

    private var operatorLink: some View {
        NavigationLink {
            OperatorScreen()
        } label: {
            CardBox {
                HStack {
                    Image(systemName: "chart.bar.xaxis").foregroundStyle(Theme.brand)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("City and operator analytics").font(.subheadline.weight(.medium))
                        Text("Idle time, demand by hour, blocked spots").font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Settings

    private var settingsCard: some View {
        let langBinding = Binding(get: { model.lang }, set: { model.setLang($0) })
        return CardBox {
            HStack {
                Label("Language", systemImage: "globe").font(.subheadline.weight(.medium))
                Spacer()
                DropdownField(selection: langBinding, options: Lang.allCases.map { ($0, $0.title) })
                    .frame(width: 160)
            }
            Divider().padding(.vertical, 8)
            Button(role: .destructive) { confirmReset = true } label: {
                Label("Reset demo data", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
