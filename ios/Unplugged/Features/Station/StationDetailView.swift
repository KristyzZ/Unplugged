import SwiftUI
import UIKit

struct StationDetailView: View {
    let stationId: String

    @Environment(AppModel.self) private var model
    @State private var pickedConnectorId: String?
    @State private var target: Double = 80
    @State private var showReport = false
    @State private var showBooking = false
    @State private var bookingConnectorId: String?
    @State private var initialized = false
    @State private var showPriceDetails = false
    @State private var showIdleDetails = false
    @Environment(\.dynamicTypeSize) private var typeSize

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
        let heldId = model.myHold.flatMap { hold in
            hold.stationId == station.id && hold.until > model.simNow() ? hold.connectorId : nil
        }
        let selectableIds = StationConnectorSelection.selectableIDs(
            connectors: station.connectors, vehicle: vehicle, heldID: heldId
        )
        let picked = StationConnectorSelection.visibleID(pickedConnectorId, selectableIDs: selectableIds, busy: busy)

        ScrollViewReader { scroll in
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
                            selectConnector(hold.connectorId, selectableIDs: selectableIds, toggle: false)
                        } onRelease: {
                            model.releaseHold()
                        }
                        .padding(.top, 12)
                    } else if let reservation = model.myReservation, reservation.stationId == station.id {
                        ReservationSummaryCard(reservation: reservation).padding(.top, 12)
                    } else if station.freeCount == 0 || model.queue?.stationId == station.id {
                        queueCard(station).padding(.top, 12)
                    }

                    SectionHeader(title: "Connectors")
                    VStack(spacing: 8) {
                        ForEach(station.connectors) { c in
                            VStack(spacing: 8) {
                                connectorRow(c, station: station, vehicle: vehicle,
                                             enabled: !busy && selectableIds.contains(c.id),
                                             selected: picked == c.id, heldForMe: heldId == c.id) {
                                    selectConnector(c.id, selectableIDs: selectableIds)
                                }
                                if picked == c.id {
                                    chargeCard(station, connector: c, vehicle: vehicle, grace: grace)
                                        .id("charge-card")
                                } else if busy && pickedConnectorId == c.id {
                                    viewSessionButton
                                }
                            }
                        }
                    }

                    if busy && !station.connectors.contains(where: { $0.id == pickedConnectorId }) {
                        viewSessionButton.padding(.top, 10)
                    }

                    SectionHeader(title: "Occupancy by hour")
                    CardBox {
                        OccupancyChart(values: station.hourlyOccupancy, currentHour: hour, highlight: best != hour ? best : nil)
                        Divider().padding(.vertical, 12)
                        StatRow {
                            StatView(label: "Usual chance of a free spot now", value: station.probabilityFree(atHour: hour).map(Fmt.estimatePct) ?? "–")
                            StatView(
                                label: "Best time in the next 6 h",
                                value: Fmt.hour(best),
                                sub: station.probabilityFree(atHour: best).map { tr("chance \(Fmt.estimatePct($0))") }
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
                guard !initialized else { return }
                initialized = true
                target = max(model.chargeLimit, min(100, model.soc + 5))
                if let heldId, !busy {
                    selectConnector(heldId, selectableIDs: selectableIds, toggle: false)
                }
            }
            .task(id: picked) {
                guard picked != nil else { return }
                // Wait for the expanded row to finish layout before resolving its
                // scroll anchor. Cancellation prevents a re-tap scrolling a stale card.
                do { try await Task.sleep(for: .milliseconds(150)) }
                catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    scroll.scrollTo("charge-card", anchor: .bottom)
                }
            }
            .onChange(of: selectableIds) { _, ids in
                guard !busy else { return }
                pickedConnectorId = StationConnectorSelection.visibleID(pickedConnectorId, selectableIDs: ids, busy: false)
            }
            .onChange(of: heldId) { _, id in
                if let id, !busy { selectConnector(id, selectableIDs: selectableIds, toggle: false) }
            }
        } // ScrollViewReader
        .sheet(isPresented: $showBooking) {
            if let connector = station.connectors.first(where: { $0.id == bookingConnectorId }) {
                ReservationBookingView(station: station, connector: connector)
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
            let summaryLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top))
            summaryLayout {
                VStack(alignment: .leading, spacing: 6) {
                    Pill(text: station.availability.label, color: station.availability.color)
                    if typeSize.isAccessibilitySize {
                        (Text("\(station.freeCount)") + Text("/\(station.workingCount) available"))
                            .font(.headline).fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(station.freeCount)").scaledFont(34, weight: .bold, relativeTo: .largeTitle)
                            Text("/\(station.workingCount) available").font(.headline).foregroundStyle(Theme.muted)
                        }
                    }
                }
                if !typeSize.isAccessibilitySize { Spacer() }
                VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing) {
                    Text(Fmt.euros(station.pricePerKwh)).font(.title2.bold())
                    Text("per kWh").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Divider().padding(.vertical, 12)
            StatRow {
                StatView(label: "Charging now", value: "\(station.count(.charging))")
                StatView(label: "Finished, parked", value: "\(station.count(.idle))")
                StatView(label: "Occupied, no charge", value: "\(station.count(.blocked))")
            }
            let actionLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            actionLayout {
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
                    Text("Demo queue position: \(entry.position). We'll hold a compatible connector for 10 min when a spot is confirmed free.")
                        .font(.subheadline).foregroundStyle(Theme.muted).padding(.top, 4)
                }
                Button("Leave queue") { model.leaveQueue() }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 12)
            } else {
                Text("All spots are taken").font(.headline)
                Text("Join the demo queue. A compatible free connector is reserved for 10 min when it is your turn.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 4)
                Button("Join queue") { model.joinQueue(station) }
                    .disabled(model.hasActiveSession || model.myReservation != nil || (model.queue != nil && model.queue?.stationId != station.id))
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 12)
            }
        }
    }

    private var viewSessionButton: some View {
        Button("You're already charging — view session") { model.tab = .charging }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("station-view-session")
    }

    private func selectConnector(_ id: String, selectableIDs: [String], toggle: Bool = true) {
        pickedConnectorId = toggle
            ? StationConnectorSelection.tapping(id, currentID: pickedConnectorId, selectableIDs: selectableIDs)
            : StationConnectorSelection.visibleID(id, selectableIDs: selectableIDs, busy: false)
        target = max(target, min(100, model.soc + 5))
        showPriceDetails = false
        showIdleDetails = false
        if pickedConnectorId != nil {
            UIAccessibility.post(notification: .announcement, argument: tr("Connector selected. Charging options expanded."))
        }
    }

    private func connectorRow(_ c: Connector, station: Station, vehicle: Vehicle,
                              enabled: Bool, selected: Bool, heldForMe: Bool,
                              onSelect: @escaping () -> Void) -> some View {
        let compatible = Charging.isCompatible(vehicle, c)
        let status = c.effectiveStatus()
        return Button(action: onSelect) {
            HStack(spacing: 12) {
                Circle().fill(status.color).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(c.type.rawValue) · \(Int(c.powerKw)) kW").font(.body.weight(.medium))
                    Text(heldForMe ? tr("Held for you") : detail(c, status: status, compatible: compatible))
                        .font(.caption)
                        .foregroundStyle(heldForMe ? Theme.brand : Theme.muted)
                    if compatible && typeSize.isAccessibilitySize {
                        Text("up to \(Int(Charging.effectivePeakKw(vehicle, c))) kW")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                if compatible && !typeSize.isAccessibilitySize {
                    Text("up to \(Int(Charging.effectivePeakKw(vehicle, c))) kW").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .padding(12)
            .frame(minHeight: 44)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Theme.brand : .clear, lineWidth: 2)
            )
            .opacity(enabled ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint(selected ? Text("Collapse charging options") : Text("Show charging options"))
        .accessibilityIdentifier("station-connector-\(c.id)")
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

    private func chargeCard(_ station: Station, connector: Connector, vehicle: Vehicle, grace: Int) -> some View {
        let estimate = Charging.chargeTime(vehicle, connector, from: model.soc, to: target)
        let price = model.chargingEstimate(at: station, connector: connector, targetSoc: target)
        let minTarget = min(100, model.soc + 5)
        return CardBox {
            Text(vehicle.name).font(.headline).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Now \(Int(model.soc)) %")
                Spacer()
                Text("To \(Int(target)) %")
            }
            .font(.subheadline)
            .padding(.top, 8)
            if minTarget < 100 {
                Slider(value: $target, in: minTarget...100, step: 1)
                    .frame(minHeight: 44)
                    .accessibilityLabel(Text("Charge target"))
                    .accessibilityValue(Text("\(Int(target)) %"))
            }
            StatRow {
                StatView(label: "Duration", value: Fmt.minutes(Double(estimate.minutes)))
                StatView(label: "Energy", value: Fmt.kwh(estimate.kwh))
                StatView(label: "Cost", value: Fmt.eur(price.charges.total))
            }
            .padding(.top, 8)
            DisclosureGroup(isExpanded: $showPriceDetails) {
                PricingBreakdownView(terms: price.terms, charges: price.charges).padding(.top, 8)
            } label: {
                Text("Price details").font(.subheadline.weight(.medium)).frame(minHeight: 44)
            }
            .tint(Theme.muted)
            DisclosureGroup(isExpanded: $showIdleDetails) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(IdleFee.tiers.enumerated()), id: \.offset) { item in
                        let tier = item.element
                        Text("From \(Int(tier.fromMin)) min: \(Fmt.euros(tier.eurPerMin)) / min")
                    }
                    Text("Maximum idle fee: \(Fmt.eur(IdleFee.capEur))")
                }.font(.caption).padding(.vertical, 8)
            } label: {
                Text("Move within \(grace) min after charging ends, or idle fees apply.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .tint(Theme.muted)
            Text("Demo session. No real payment.")
                .font(.caption).foregroundStyle(Theme.muted)
                .padding(.top, 6)
            Button("Start & pay") {
                // Keep Explore's destination and selection alive. The model
                // switches to Charging; returning shows this same station.
                model.startCharging(at: station, connector: connector, targetSoc: target)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("station-start-charge")
            .padding(.top, 10)
            if model.myReservation == nil && model.queue == nil {
                Button("Reserve connector") {
                    bookingConnectorId = connector.id
                    showBooking = true
                }
                .buttonStyle(SecondaryButtonStyle()).padding(.top, 8)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("station-charge-card")
    }

}

/// "This spot is held for you" with the time left to plug in.
private struct HoldCard: View {
    let hold: SpotHold
    let onCharge: () -> Void
    let onRelease: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

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
                Text(hold.bookedAt != nil
                     ? "Begin charging within 10 min of the reserved start, or the spot is released."
                     : "A driver just left and you were next in line. Plug in before the time runs out, or it goes to the next person.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 10)
                let actionLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
                actionLayout {
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

/// Selection policy shared by row highlighting and the single inline card.
enum StationConnectorSelection {
    static func selectableIDs(connectors: [Connector], vehicle: Vehicle, heldID: String?, now: Date = .now) -> [String] {
        connectors.filter { connector in
            let status = connector.effectiveStatus(at: now)
            return Charging.isCompatible(vehicle, connector)
                && (connector.isConfirmedAvailable(at: now) || (connector.id == heldID && status == .reserved))
        }.map(\.id)
    }

    static func visibleID(_ currentID: String?, selectableIDs: [String], busy: Bool) -> String? {
        guard !busy, let currentID, selectableIDs.contains(currentID) else { return nil }
        return currentID
    }

    static func tapping(_ id: String, currentID: String?, selectableIDs: [String]) -> String? {
        guard selectableIDs.contains(id) else { return visibleID(currentID, selectableIDs: selectableIDs, busy: false) }
        return currentID == id ? nil : id
    }
}
