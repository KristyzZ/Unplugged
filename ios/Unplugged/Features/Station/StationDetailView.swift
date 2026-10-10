import SwiftUI

struct StationDetailView: View {
    let stationId: String

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pickedConnectorId: String?
    @State private var target: Double = 80
    @State private var showReport = false

    var body: some View {
        Group {
            if let station = model.stations.first(where: { $0.id == stationId }) {
                content(station)
            } else {
                ContentUnavailableView("Station not found", systemImage: "bolt.slash")
            }
        }
        .tabBarClearance()
        .screenBackdrop()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func content(_ station: Station) -> some View {
        let vehicle = model.vehicle
        let op = DemoData.chargeOperator(station.operatorId)
        let hour = Calendar.current.component(.hour, from: .now)
        let demand = station.demandLevel(hour: hour)
        let grace = IdleFee.graceMinutes(demand: demand)
        let best = station.bestHour(from: hour)
        let busy = model.hasActiveSession
        let picked = station.connectors.first { $0.id == pickedConnectorId }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(station.name).font(.largeTitle.bold())
                    HStack(spacing: 6) {
                        Circle().fill(op.color).frame(width: 8, height: 8)
                        Text("\(op.name) · \(station.address), \(station.city)")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                }
                .padding(.bottom, 16)

                statusCard(station)

                if station.freeCount == 0 {
                    queueCard(station).padding(.top, 12)
                }

                SectionHeader(title: "Connectors")
                VStack(spacing: 8) {
                    ForEach(station.connectors) { c in
                        connectorRow(c, vehicle: vehicle, selectable: !busy)
                    }
                }

                if let picked, !busy {
                    chargeCard(station, connector: picked, vehicle: vehicle, grace: grace, demand: demand)
                        .padding(.top, 12)
                }
                if busy {
                    Button("You're already charging — view session") { model.tab = .charging }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.top, 10)
                }

                SectionHeader(title: "Occupancy by hour")
                CardBox {
                    OccupancyChart(values: station.hourlyOccupancy, currentHour: hour, highlight: best != hour ? best : nil)
                    Divider().padding(.vertical, 12)
                    StatRow {
                        StatView(label: "Usual chance of a free spot now", value: Fmt.pct(station.probabilityFree(atHour: hour)))
                        StatView(
                            label: "Best time in the next 6 h",
                            value: Fmt.hour(best),
                            sub: tr("chance \(Fmt.pct(station.probabilityFree(atHour: best)))")
                        )
                    }
                }

                if !station.amenities.isEmpty {
                    SectionHeader(title: "Nearby")
                    HStack {
                        ForEach(station.amenities, id: \.self) { Pill(text: $0) }
                    }
                }
            }
            .padding(16)
        }
        .sheet(isPresented: $showReport) {
            NavigationStack {
                ReportContent(stationId: station.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showReport = false }
                        }
                    }
            }
        }
    }

    private func statusCard(_ station: Station) -> some View {
        CardBox {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Pill(text: station.availability.label, color: station.availability.color)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(station.freeCount)").scaledFont(34, weight: .bold, relativeTo: .largeTitle)
                        Text("/\(station.workingCount) available").font(.headline).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(String(format: "%.2f €", station.pricePerKwh)).font(.title2.bold())
                    Text("per kWh").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Divider().padding(.vertical, 12)
            StatRow {
                StatView(label: "Charging now", value: "\(station.count(.charging))")
                StatView(label: "Finished, parked", value: "\(station.count(.idle))")
                StatView(label: "Occupied, no charge", value: "\(station.count(.blocked))")
            }
            HStack(spacing: 8) {
                if let url = URL(string: "http://maps.apple.com/?daddr=\(station.lat),\(station.lng)") {
                    Link(destination: url) { Label("Route", systemImage: "arrow.triangle.turn.up.right.diamond") }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button { showReport = true } label: { Label("Report", systemImage: "exclamationmark.triangle") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 14)
        }
    }

    private func queueCard(_ station: Station) -> some View {
        let soonest = station.connectors.compactMap(\.etaMinutes).min() ?? 60
        let inQueue = model.queue?.stationId == station.id
        return CardBox(stroke: Theme.warn) {
            Text("All spots are taken").font(.headline)
            Text("Join the virtual queue — we'll notify you when a spot frees up. The next free spot is expected in \(Fmt.minutes(Double(soonest)))")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .padding(.top, 4)
            if inQueue {
                HStack {
                    Text("You're in the queue: position **\(model.queue?.position ?? 1)**").font(.subheadline)
                    Spacer()
                    Button("Leave queue") { model.leaveQueue() }
                }
                .padding(.top, 12)
            } else {
                Button("Join queue") { model.joinQueue(station) }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 12)
            }
        }
    }

    private func connectorRow(_ c: Connector, vehicle: Vehicle, selectable: Bool) -> some View {
        let compatible = Charging.isCompatible(vehicle, c)
        let enabled = selectable && compatible && c.status == .available
        let selected = pickedConnectorId == c.id
        return Button {
            pickedConnectorId = c.id
            target = max(target, min(100, model.soc + 5))
        } label: {
            HStack(spacing: 12) {
                Circle().fill(c.status.color).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(c.type.rawValue) · \(Int(c.powerKw)) kW").font(.body.weight(.medium))
                    Text(detail(c, compatible: compatible)).font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                if compatible {
                    Text("up to \(Int(Charging.effectivePeakKw(vehicle, c))) kW").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Theme.brand : .clear, lineWidth: 2)
            )
            .opacity(enabled ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func detail(_ c: Connector, compatible: Bool) -> String {
        var text = c.status.label
        if c.status == .charging, let eta = c.etaMinutes {
            text += tr(" · frees up ~\(Fmt.clock(Date().addingTimeInterval(Double(eta) * 60)))")
        }
        if c.status == .idle, let idle = c.idleMinutes {
            text += tr(" · parked for \(idle) min")
        }
        if !compatible { text += tr(" · not compatible with your car") }
        return text
    }

    private func chargeCard(_ station: Station, connector: Connector, vehicle: Vehicle, grace: Int, demand: Double) -> some View {
        let estimate = Charging.chargeTime(vehicle, connector, from: model.soc, to: target)
        let price = model.chargingEstimate(at: station, connector: connector, targetSoc: target)
        let minTarget = min(100, model.soc + 5)
        let tiersText = IdleFee.tiers.map { String(format: "%.2f €", $0.eurPerMin) }.joined(separator: " → ")
        let finishText = Fmt.clock(Date().addingTimeInterval(Double(estimate.minutes) * 60))
        return CardBox {
            Text("Charging: \(vehicle.name)").font(.headline)
            HStack {
                Text("Now \(Int(model.soc)) %")
                Spacer()
                Text("To \(Int(target)) %")
            }
            .font(.subheadline)
            .padding(.top, 10)
            SocBar(value: model.soc, target: target).padding(.top, 4)
            if minTarget < 100 {
                Slider(value: $target, in: minTarget...100, step: 1).padding(.top, 6)
            }
            StatRow {
                StatView(label: "Duration", value: Fmt.minutes(Double(estimate.minutes)), sub: tr("ends ~\(finishText)"))
                StatView(label: "Energy", value: String(format: "%.1f kWh", estimate.kwh))
                StatView(label: "Cost", value: Fmt.eur(price.charges.total))
            }
            .padding(.top, 10)
            PricingBreakdownView(terms: price.terms, charges: price.charges)
                .padding(.top, 12)
            Text("Once charging ends you'll have **\(grace) min** to move your car (current demand \(Fmt.pct(demand))). After that the idle fee grows: \(tiersText) per min. Move on time to earn points.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .padding(10)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 12)
            Button("Start and pay with Unplugged") {
                model.startCharging(at: station, connector: connector, targetSoc: target)
                pickedConnectorId = nil
                // Leave the map stack at its root; the app switches to the Charging tab.
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 12)
        }
    }
}
