import MapKit
import SwiftUI

/// Trip planning: where you're going and how much battery you have →
/// where to stop, how long to charge, what you arrive with.
struct PlanScreen: View {
    @Environment(AppModel.self) private var model
    @State private var originId = "vilnius"
    @State private var destinationId = "klaipeda"
    @State private var plan: TripPlan?
    @State private var plannedFrom: Place?
    @State private var plannedTo: Place?
    @State private var departure = Date()

    private var origin: Place { DemoData.places.first { $0.id == originId } ?? DemoData.places[0] }
    private var destination: Place { DemoData.places.first { $0.id == destinationId } ?? DemoData.places[1] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    routeCard
                    batteryCard
                    Button("Plan route", action: runPlan)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(originId == destinationId)
                        .opacity(originId == destinationId ? 0.5 : 1)
                    if let plan, let from = plannedFrom, let to = plannedTo {
                        results(plan, from: from, to: to)
                            .padding(.top, 12)
                    } else {
                        Text("We'll pick charging stops that fit your car and are usually free when you get there.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                    }
                }
                .padding(16)
            }
            .tabBarClearance()
            .screenBackdrop()
            .navigationTitle("Plan")
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { ScreenHeader(title: "Plan") }
            .navigationDestination(for: String.self) { id in
                StationDetailView(stationId: id)
            }
            // Inputs changed: the old result no longer applies.
            .onChange(of: originId) { plan = nil }
            .onChange(of: destinationId) { plan = nil }
            .onChange(of: model.vehicleId) { plan = nil }
        }
    }

    private func runPlan() {
        departure = Date()
        plannedFrom = origin
        plannedTo = destination
        withAnimation(.spring(duration: 0.4)) {
            plan = TripPlanner.plan(TripInput(
                vehicle: model.vehicle,
                startSoc: model.soc,
                origin: origin.latLng,
                destination: destination.latLng,
                stations: model.stations,
                departure: departure
            ))
        }
    }

    // MARK: Inputs

    private var routeCard: some View {
        CardBox {
            HStack(spacing: 12) {
                // From ○ ⋮ ● To guide, like a maps app.
                VStack(spacing: 4) {
                    Circle().strokeBorder(Theme.muted, lineWidth: 2).frame(width: 12, height: 12)
                    ForEach(0..<3) { _ in Circle().fill(Theme.muted.opacity(0.5)).frame(width: 3, height: 3) }
                    Image(systemName: "mappin.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.brand)
                }
                VStack(spacing: 0) {
                    placeMenu(label: "From", selection: $originId)
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                    placeMenu(label: "To", selection: $destinationId)
                }
                Button {
                    withAnimation { (originId, destinationId) = (destinationId, originId) }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 40, height: 40)
                        .glass(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Swap start and destination"))
            }
        }
    }

    private func placeMenu(label: LocalizedStringKey, selection: Binding<String>) -> some View {
        let name = DemoData.places.first { $0.id == selection.wrappedValue }?.name ?? ""
        return Menu {
            Picker(label, selection: selection) {
                ForEach(DemoData.places) { p in Text(p.name).tag(p.id) }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.caption).foregroundStyle(Theme.muted)
                    Text(name).font(.body.weight(.medium)).foregroundStyle(Theme.text)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var batteryCard: some View {
        let vehicle = model.vehicle
        let socBinding = Binding(get: { model.soc }, set: { model.setSoc($0); plan = nil })
        return CardBox {
            HStack(alignment: .firstTextBaseline) {
                Text("Battery now").font(.subheadline).foregroundStyle(Theme.muted)
                Spacer()
                Text("\(Int(model.soc)) %")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
            }
            Slider(value: socBinding, in: 5...100, step: 1)
                .tint(model.soc < 20 ? Theme.bad : Theme.brand)
            HStack {
                Text("≈ \(Int(vehicle.rangeKm(soc: model.soc))) km range")
                Spacer()
                Button(vehicle.name) { model.tab = .profile }
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
    }

    // MARK: Results

    @ViewBuilder
    private func results(_ plan: TripPlan, from: Place, to: Place) -> some View {
        if !plan.feasible {
            CardBox(stroke: Theme.bad) {
                Text("**Can't make this trip.** \(plan.message ?? "")").font(.subheadline)
            }
        }

        // Summary first: how long, how far, what you arrive with.
        CardBox {
            Text(Fmt.minutes(Double(plan.driveMinutes + plan.chargeMinutes)))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
            Text(summaryLine(plan))
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .padding(.top, 2)
        }

        routeMap(plan, from: from, to: to)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

        // One list, top to bottom: leave → stops → arrive.
        ListCard {
            endpointRow(systemImage: "circle", title: from.name, detail: tr("Leave \(Fmt.clock(departure)) with \(Int(model.soc)) %"))
            ForEach(plan.stops) { stop in
                RowDivider()
                NavigationLink(value: stop.station.id) { stopRow(stop) }
                    .buttonStyle(.plain)
            }
            RowDivider()
            endpointRow(systemImage: "mappin", title: to.name, detail: tr("Arrive \(Fmt.clock(plan.arriveAt)) with \(plan.arriveSoc) %"))
        }
    }

    private func summaryLine(_ plan: TripPlan) -> String {
        var parts = ["\(plan.totalKm) km", Fmt.stops(plan.stops.count)]
        if plan.costEur > 0 { parts.append(tr("\(Fmt.eur(plan.costEur)) charging")) }
        parts.append(tr("arrive with \(plan.arriveSoc) %"))
        // Keep "13 %" together when the line wraps.
        return parts.joined(separator: " · ").replacingOccurrences(of: " %", with: "\u{00A0}%")
    }

    private func endpointRow(systemImage: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemImage: systemImage, color: Theme.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(Theme.text)
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func stopRow(_ stop: TripStop) -> some View {
        let likely = stop.freeProbability > 0.7 ? Theme.ok : stop.freeProbability > 0.4 ? Theme.warn : Theme.bad
        return HStack(spacing: 12) {
            IconBadge(systemImage: "bolt.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.station.name).font(.body.weight(.medium)).foregroundStyle(Theme.text)
                Text(tr("Charge \(Fmt.minutes(Double(stop.chargeMinutes))) to \(stop.departSoc) %"))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                Text(tr("Usually free: \(Fmt.pct(stop.freeProbability))"))
                    .font(.caption)
                    .foregroundStyle(likely)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.clock(stop.arriveAt)).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                Text(Fmt.eur(stop.costEur)).font(.caption).foregroundStyle(Theme.muted)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func routeMap(_ plan: TripPlan, from: Place, to: Place) -> some View {
        let coords = [from.latLng.coordinate] + plan.stops.map(\.station.coordinate) + [to.latLng.coordinate]
        return Map(initialPosition: .automatic) {
            MapPolyline(coordinates: coords)
                .stroke(Theme.brand, lineWidth: 4)
            Marker(from.name, systemImage: "car.fill", coordinate: from.latLng.coordinate)
                .tint(Theme.muted)
            ForEach(plan.stops) { stop in
                Annotation(stop.station.name, coordinate: stop.station.coordinate, anchor: .bottom) {
                    StationPin(station: stop.station, emphasized: true)
                }
            }
            Marker(to.name, systemImage: "flag.checkered", coordinate: to.latLng.coordinate)
                .tint(Theme.brand)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .id("\(from.id)-\(to.id)-\(plan.stops.map(\.id).joined())")
    }
}
