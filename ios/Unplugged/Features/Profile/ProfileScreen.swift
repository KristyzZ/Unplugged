import SwiftUI

/// Your car at a glance, then a short list. Each detail lives on its own page.
struct ProfileScreen: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    carSummary
                    accountList
                    settingsList
                    moreList
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

    // MARK: Car summary

    private var carSummary: some View {
        let vehicle = model.vehicle
        return NavigationLink {
            CarScreen()
        } label: {
            CardBox {
                HStack(spacing: 14) {
                    IconBadge(systemImage: "car.side.fill").scaleEffect(1.25).frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(vehicle.name).font(.headline).foregroundStyle(Theme.text)
                        Text(tr("\(Int(model.soc)) % · ≈ \(Int(vehicle.rangeKm(soc: model.soc))) km range"))
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    ListRowValue(value: nil)
                }
                SocBar(value: model.soc, height: 6).padding(.top, 12)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Lists

    private var accountList: some View {
        let payment = DemoData.paymentMethods.first { $0.id == model.defaultPaymentId }
        let plans = model.activePlanIds.count
        let tier = Points.tier(for: model.lifetimePoints).current.name
        return ListCard {
            NavigationLink { RewardsScreen() } label: {
                ListRow(systemImage: "star.fill", title: "Points", value: "\(model.points) · \(tier)", color: Theme.warn)
            }
            RowDivider()
            NavigationLink { PaymentScreen() } label: {
                ListRow(systemImage: "creditcard.fill", title: "Payment", value: payment?.title)
            }
            RowDivider()
            NavigationLink { PlansScreen() } label: {
                ListRow(systemImage: "ticket.fill", title: "Operator plans", value: plans == 0 ? tr("None") : tr("\(plans) active"))
            }
        }
        .buttonStyle(.plain)
    }

    private var settingsList: some View {
        let lockScreen = Binding(get: { model.lockScreenEnabled }, set: { model.setLockScreen($0) })
        return ListCard {
            ListRow(systemImage: "lock.iphone", title: "Charging on Lock Screen") {
                Toggle("", isOn: lockScreen).labelsHidden().tint(Theme.brand)
            }
            RowDivider()
            ListRow(systemImage: "globe", title: "Language") {
                Menu {
                    Picker("Language", selection: Binding(get: { model.lang }, set: { model.setLang($0) })) {
                        ForEach(Lang.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(model.lang.title)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var moreList: some View {
        ListCard {
            NavigationLink { OperatorScreen() } label: {
                ListRow(systemImage: "chart.bar.xaxis", title: "City and operator analytics", color: Theme.ok)
            }
            .buttonStyle(.plain)
            RowDivider()
            Button { confirmReset = true } label: {
                ListRow(systemImage: "arrow.counterclockwise", title: "Reset demo data", color: Theme.bad) { EmptyView() }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Car

private struct CarScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let vehicle = model.vehicle
        let socBinding = Binding(get: { model.soc }, set: { model.setSoc($0) })
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CardBox {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Battery now").font(.subheadline).foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(Int(model.soc)) %")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                    }
                    Slider(value: socBinding, in: 1...100, step: 1).tint(Theme.brand)
                    HStack {
                        StatView(label: "Range now", value: Fmt.km(vehicle.rangeKm(soc: model.soc)))
                        StatView(label: "At 80 %", value: Fmt.km(vehicle.rangeKm(soc: 80)))
                        StatView(label: "Full", value: Fmt.km(vehicle.rangeKm(soc: 100)))
                    }
                    .padding(.top, 8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your car").font(.headline).foregroundStyle(Theme.text)
                    ListCard {
                        ForEach(Array(DemoData.vehicles.enumerated()), id: \.element.id) { item in
                            let v = item.element
                            if item.offset > 0 { RowDivider() }
                            Button { model.setVehicle(v.id) } label: {
                                ListRow(systemImage: "car.fill", title: LocalizedStringKey(v.name), color: v.id == vehicle.id ? Theme.brand : Theme.muted) {
                                    Text("\(Int(v.batteryKwh)) kWh").font(.subheadline).foregroundStyle(Theme.muted)
                                    if v.id == vehicle.id {
                                        Image(systemName: "checkmark").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.brand)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Max charging \(Int(vehicle.maxDcKw)) kW DC / \(Int(vehicle.maxAcKw)) kW AC · \(vehicle.connectors.map(\.rawValue).joined(separator: ", ")). Used to show only chargers that fit and to plan trips.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(16)
        }
        .tabBarClearance()
        .screenBackdrop()
        .navigationTitle("Car")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Payment

private struct PaymentScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ListCard {
                    ForEach(Array(DemoData.paymentMethods.enumerated()), id: \.element.id) { item in
                        let method = item.element
                        if item.offset > 0 { RowDivider() }
                        Button { model.setDefaultPayment(method.id) } label: {
                            ListRow(systemImage: method.systemImage, title: LocalizedStringKey(method.title)) {
                                if model.defaultPaymentId == method.id {
                                    Image(systemName: "checkmark").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.brand)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Charging is paid with the checked method. Demo only: no real payments are made.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .tabBarClearance()
        .screenBackdrop()
        .navigationTitle("Payment")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Operator plans

private struct PlansScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Already pay for an operator's plan? Turn it on and we'll show your discounted price at their stations.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                ListCard {
                    ForEach(Array(DemoData.plans.enumerated()), id: \.element.id) { item in
                        let plan = item.element
                        let op = DemoData.chargeOperator(plan.id)
                        if item.offset > 0 { RowDivider() }
                        HStack(spacing: 12) {
                            IconBadge(systemImage: "ticket.fill", color: op.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plan.name).font(.body.weight(.medium)).foregroundStyle(Theme.text)
                                Text(plan.perk).font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { model.activePlanIds.contains(plan.id) },
                                set: { model.setPlan(plan.id, active: $0) }
                            ))
                            .labelsHidden()
                            .tint(Theme.brand)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                    }
                }
                Text("Demo plans. Linking real accounts needs the operator's sign-in.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .tabBarClearance()
        .screenBackdrop()
        .navigationTitle("Operator plans")
        .navigationBarTitleDisplayMode(.inline)
    }
}
