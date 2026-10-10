import SwiftUI

struct ReservationBookingView: View {
    let station: Station
    let connector: Connector
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var startNow = true
    @State private var startsAt = Date().addingTimeInterval(900)
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                CardBox {
                    Text(station.name).font(.headline)
                    Text("\(connector.type.label) · \(Int(connector.powerKw)) kW")
                        .font(.subheadline).foregroundStyle(Theme.muted).padding(.top, 4)
                    Toggle("Start now", isOn: $startNow).padding(.vertical, 12)
                    if !startNow {
                        DatePicker("Charging start", selection: $startsAt,
                                   in: Date.now...Date.now.addingTimeInterval(ReservationRules.bookingHorizon / max(1, model.speed)),
                                   displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.graphical)
                    }
                    Text("Begin charging within 10 min of the reserved start, or the spot is released.")
                        .font(.subheadline).padding(.vertical, 12)
                    Text("Demo reservation. No real charger is guaranteed. Times follow the demo clock speed.")
                        .font(.caption).foregroundStyle(Theme.muted)
                    if failed {
                        Text("Reservation unavailable. Refresh the station or cancel your existing queue or reservation.")
                            .font(.caption).foregroundStyle(Theme.warn).padding(.top, 10)
                    }
                    Button("Confirm reservation") {
                        let now = model.simNow()
                        let delay = startsAt.timeIntervalSinceNow
                        guard startNow || delay > 0 else { failed = true; return }
                        let start = startNow ? now : now.addingTimeInterval(delay * max(1, model.speed))
                        // Re-read the current connector; the sheet's initial snapshot may be old.
                        guard let latest = model.stations.first(where: { $0.id == station.id }),
                              let current = latest.connectors.first(where: { $0.id == connector.id }) else { failed = true; return }
                        if model.reserveConnector(at: latest, connector: current, startsAt: start, now: now) { dismiss() }
                        else { failed = true }
                    }
                    .buttonStyle(PrimaryButtonStyle()).padding(.top, 16)
                }.padding(16)
            }
            .screenBackdrop().navigationTitle("Reserve connector")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                startsAt = Date().addingTimeInterval(min(900, ReservationRules.bookingHorizon / max(1, model.speed) / 2))
            }
        }
    }
}

struct ReservationSummaryCard: View {
    let reservation: SpotHold
    @Environment(AppModel.self) private var model

    var body: some View {
        CardBox(stroke: Theme.brand) {
            Text("Demo reservation").font(.caption).foregroundStyle(Theme.muted)
            Text("Upcoming reservation").font(.headline)
            Text(reservation.connectorLabel).font(.subheadline).padding(.top, 4)
            Text("Starts \(Fmt.clock(model.realDate(reservation.startedAt))) · expires \(Fmt.clock(model.realDate(reservation.until)))")
                .font(.subheadline).foregroundStyle(Theme.muted).padding(.top, 8)
            Text("Begin charging within 10 min of the reserved start, or the spot is released.")
                .font(.caption).foregroundStyle(Theme.muted).padding(.top, 8)
            Button("Cancel reservation") { model.releaseHold() }
                .buttonStyle(SecondaryButtonStyle()).padding(.top, 12)
        }
    }
}
