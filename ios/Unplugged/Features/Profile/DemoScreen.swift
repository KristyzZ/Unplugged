import SwiftUI

/// Demo controls in one place: how fast the demo clock runs, fake
/// reservations (yours and other drivers'), demo stations and reset.
struct DemoScreen: View {
    @Environment(AppModel.self) private var model
    @State private var reserveFailed = false
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Try reservations and timed features without waiting. Everything here is demo data: nothing is booked for real.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                section("Time speed") { timeSpeed }
                section("Your reservation") { yourReservation }
                section("Other drivers") { otherDrivers }
                section("Data") { data }
            }
            .padding(16)
        }
        .tabBarClearance()
        .screenBackdrop()
        .navigationTitle("Demo")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset all demo data?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { model.resetDemo() }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(Theme.text)
            content()
        }
    }

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Time speed

    private var timeSpeed: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardBox {
                Picker("Demo: speed up time", selection: Binding(get: { model.speed }, set: { model.setSpeed($0) })) {
                    ForEach([1.0, 10, 60, 300], id: \.self) { Text("\(Int($0))×").tag($0) }
                }
                .pickerStyle(.segmented)
                // Ticks every second so you can watch the demo clock run at the chosen speed.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack {
                        Text("Demo clock").foregroundStyle(Theme.muted)
                        Spacer()
                        Text(model.simNow().formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(L10n.locale)))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
                .padding(.top, 12)
            }
            caption("Speeds up time so you can see the finished notice, the free minutes and the idle fee.")
        }
    }

    // MARK: Your reservation

    @ViewBuilder
    private var yourReservation: some View {
        if let reservation = model.myReservation {
            ReservationSummaryCard(reservation: reservation)
            Button { model.openStation(reservation.stationId) } label: {
                Label("Open station", systemImage: "mappin.and.ellipse")
            }
            .buttonStyle(SecondaryButtonStyle())
        } else {
            let blocked = model.hasActiveSession || model.queue != nil
            ListCard {
                reserveRow("Reserve now", systemImage: "calendar.badge.checkmark", minutes: 0)
                RowDivider()
                reserveRow("Reserve in 15 min", systemImage: "calendar.badge.clock", minutes: 15)
                RowDivider()
                reserveRow("Reserve in 1 h", systemImage: "calendar", minutes: 60)
            }
            .disabled(blocked)
            .opacity(blocked ? 0.6 : 1)
            if blocked {
                caption("Stop charging or leave the queue before making a reservation.")
            } else if reserveFailed {
                Text("No free charger to reserve right now. Try again in a moment.")
                    .font(.caption)
                    .foregroundStyle(Theme.warn)
            }
            caption("Books the nearest free charger you can reserve in the app. Times follow the demo clock.")
        }
    }

    private func reserveRow(_ title: LocalizedStringKey, systemImage: String, minutes: Double) -> some View {
        Button {
            reserveFailed = !model.fakeReservation(startingIn: minutes)
        } label: {
            ListRow(systemImage: systemImage, title: title) { EmptyView() }
        }
        .buttonStyle(.plain)
    }

    // MARK: Other drivers

    private var otherDrivers: some View {
        VStack(alignment: .leading, spacing: 8) {
            ListCard {
                Button { model.fakeOthersReservation() } label: {
                    ListRow(systemImage: "person.2.fill", title: "Another driver reserves a spot", color: Theme.warn) { EmptyView() }
                }
                .buttonStyle(.plain)
                ForEach(model.othersReservations) { hold in
                    RowDivider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hold.stationName).font(.subheadline).foregroundStyle(Theme.text)
                            Text(hold.connectorLabel).font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text("Reserved until \(Fmt.clock(model.realDate(hold.until)))")
                            .font(.caption)
                            .foregroundStyle(Theme.warn)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .accessibilityElement(children: .combine)
                }
            }
            caption("Marks the nearest free charger as reserved for 10 min, as if someone else booked it.")
        }
    }

    // MARK: Data

    private var data: some View {
        ListCard {
            ListRow(systemImage: "bolt.horizontal.circle", title: "Use demo stations") {
                Toggle("", isOn: Binding(get: { model.stationSource == .demo },
                                         set: { model.setStationSource($0 ? .demo : .real) }))
                    .labelsHidden().tint(Theme.brand)
            }
            Text("Show invented stations instead of the live ones, for offline demos.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            RowDivider()
            Button { confirmReset = true } label: {
                ListRow(systemImage: "arrow.counterclockwise", title: "Reset demo data", color: Theme.bad) { EmptyView() }
            }
            .buttonStyle(.plain)
        }
    }
}
