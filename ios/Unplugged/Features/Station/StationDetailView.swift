import SwiftUI
import UIKit

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

                if let listing = model.hostListing(forStation: station.id) {
                    HostedStationCard(listing: listing).padding(.bottom, 12)
                }

                statusCard(station)

                // Where the status and price come from, and a clear warning when it is stale.
                Text(station.provenanceSummary())
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 8)
                    .accessibilityLabel(Text(station.provenanceSummary()))

                if let hold = model.myHold, hold.stationId == station.id {
                    HoldCard(hold: hold) {
                        pickedConnectorId = hold.connectorId
                        target = max(target, min(100, model.soc + 5))
                    } onRelease: {
                        model.releaseHold()
                    }
                    .padding(.top, 12)
                } else if station.freeCount == 0 || model.queue?.stationId == station.id {
                    queueCard(station).padding(.top, 12)
                }

                SectionHeader(title: "Connectors")
                VStack(spacing: 8) {
                    ForEach(station.connectors) { c in
                        connectorRow(c, station: station, vehicle: vehicle, selectable: !busy)
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
                        StatView(label: "Usual chance of a free spot now", value: station.probabilityFree(atHour: hour).map(Fmt.pct) ?? "–")
                        StatView(
                            label: "Best time in the next 6 h",
                            value: Fmt.hour(best),
                            sub: station.probabilityFree(atHour: best).map { tr("chance \(Fmt.pct($0))") }
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
        .onAppear {
            target = model.chargeLimit
            // Arriving at a spot held for you: it's already picked.
            if let hold = model.myHold, hold.stationId == station.id, !busy {
                pickedConnectorId = hold.connectorId
            }
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
        let entry = model.queue?.stationId == station.id ? model.queue : nil
        return CardBox(stroke: Theme.warn) {
            if let entry {
                Text("You're in the queue").font(.headline)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let wait = Fmt.minutes(max(1, (entry.nextEventAt ?? .now).timeIntervalSince(model.simNow()) / 60))
                    Group {
                        if entry.position == 1 {
                            Text("You're next. When a car leaves, its charger is held for you for \(Int(SpotHold.minutes)) min. Expected in about \(wait).")
                        } else {
                            Text("\(entry.position) in line. The next car is expected to leave in about \(wait).")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 4)
                }
                Button("Leave queue") { model.leaveQueue() }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 12)
            } else {
                Text("All spots are taken").font(.headline)
                Text("Join the queue. When a car leaves, its charger is held for the next driver for \(Int(SpotHold.minutes)) min, so nobody can grab it first.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 4)
                Button("Join queue") { model.joinQueue(station) }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 12)
            }
        }
    }

    private func connectorRow(_ c: Connector, station: Station, vehicle: Vehicle, selectable: Bool) -> some View {
        let compatible = Charging.isCompatible(vehicle, c)
        let status = c.effectiveStatus()
        let heldForMe = model.myHold.map { $0.stationId == station.id && $0.connectorId == c.id } ?? false
        let enabled = selectable && compatible && (c.isConfirmedAvailable() || heldForMe)
        let selected = pickedConnectorId == c.id
        return Button {
            pickedConnectorId = c.id
            target = max(target, min(100, model.soc + 5))
        } label: {
            HStack(spacing: 12) {
                Circle().fill(status.color).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(c.type.rawValue) · \(Int(c.powerKw)) kW").font(.body.weight(.medium))
                    Text(heldForMe ? tr("Held for you") : detail(c, status: status, compatible: compatible))
                        .font(.caption)
                        .foregroundStyle(heldForMe ? Theme.brand : Theme.muted)
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

    private func detail(_ c: Connector, status: ConnectorStatus, compatible: Bool) -> String {
        var text = status.label
        if status == .charging, let eta = c.etaMinutes {
            text += tr(" · frees up ~\(Fmt.clock(Date().addingTimeInterval(Double(eta) * 60)))")
        }
        if status == .idle, let idle = c.idleMinutes {
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

/// "This spot is held for you" with the time left to plug in.
private struct HoldCard: View {
    let hold: SpotHold
    let onCharge: () -> Void
    let onRelease: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let left = max(0, hold.until.timeIntervalSince(model.simNow()))
            CardBox(stroke: Theme.brand) {
                HStack(spacing: 14) {
                    ProgressRing(progress: left / max(1, hold.duration), color: Theme.brand, lineWidth: 5) {
                        Text(Fmt.mmss(left))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                    }
                    .frame(width: 60, height: 60)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("This spot is held for you").font(.headline).foregroundStyle(Theme.text)
                        Text("\(hold.connectorLabel) · until \(Fmt.clock(model.realDate(hold.until)))")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                }
                Text("A driver just left and you were next in line. Plug in before the time runs out, or it goes to the next person.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 10)
                HStack(spacing: 10) {
                    Button("Release", action: onRelease).buttonStyle(SecondaryButtonStyle())
                    Button("Charge here", action: onCharge).buttonStyle(PrimaryButtonStyle())
                }
                .padding(.top, 12)
            }
        }
    }
}

/// A charger rented out by its owner: their photo, when it's free and how to find it.
private struct HostedStationCard: View {
    let listing: HostListing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let photo = HostPhotoStore.load(listing.photoFile) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                    .overlay { Image(uiImage: photo).resizable().scaledToFill() }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityElement()
                    .accessibilityLabel(Text("Photo of the charger"))
            }
            CardBox {
                HStack(spacing: 12) {
                    IconBadge(systemImage: listing.kind.systemImage, color: Color(hex: "DB2777"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(listing.kind == .homeowner ? "Shared by a homeowner" : "Shared by the station owner")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Text(listing.schedule.summary).font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    Pill(text: listing.instantBook ? tr("Instant booking") : tr("Request to book"), color: Theme.info)
                }
                if !listing.accessNotes.isEmpty {
                    Text(listing.accessNotes).font(.subheadline).foregroundStyle(Theme.text).padding(.top, 10)
                }
            }
        }
    }
}
