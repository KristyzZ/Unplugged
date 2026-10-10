import MapKit
import SwiftUI

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
                VStack(alignment: .leading, spacing: 0) {
                    Text("We'll plan where and how much to charge based on your car, route and station occupancy.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .padding(.bottom, 12)
                    form
                    if let plan, let from = plannedFrom, let to = plannedTo {
                        results(plan, from: from, to: to)
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
        }
    }

    private var form: some View {
        let vehicle = model.vehicle
        let socBinding = Binding(get: { model.soc }, set: { model.setSoc($0) })
        return CardBox {
            Text("Car").font(.subheadline.weight(.medium))
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vehicle.name).font(.headline)
                    Text("\(Int(vehicle.batteryKwh)) kWh · max \(Int(vehicle.maxDcKw)) kW DC")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Change") { model.tab = .profile }
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.top, 2)
            .padding(.bottom, 12)

            Text("Current battery level: \(Int(model.soc)) %").font(.subheadline.weight(.medium))
            Slider(value: socBinding, in: 5...100, step: 1)
            SocBar(value: model.soc)
            Text("≈ \(Int(vehicle.rangeKm(soc: model.soc))) km of range")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .padding(.top, 4)
                .padding(.bottom, 12)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading) {
                    Text("From").font(.subheadline.weight(.medium))
                    placePicker(selection: $originId)
                }
                VStack(alignment: .leading) {
                    Text("To").font(.subheadline.weight(.medium))
                    placePicker(selection: $destinationId)
                }
            }

            Button("Plan trip") {
                departure = Date()
                plannedFrom = origin
                plannedTo = destination
                withMotion {
                    plan = TripPlanner.plan(TripInput(
                        vehicle: vehicle,
                        startSoc: model.soc,
                        origin: origin.latLng,
                        destination: destination.latLng,
                        stations: model.stations,
                        departure: departure
                    ))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(originId == destinationId)
            .opacity(originId == destinationId ? 0.5 : 1)
            .padding(.top, 16)
        }
    }

    private func placePicker(selection: Binding<String>) -> some View {
        DropdownField(selection: selection, options: DemoData.places.map { ($0.id, $0.name) })
    }

    @ViewBuilder
    private func results(_ plan: TripPlan, from: Place, to: Place) -> some View {
        SectionHeader(title: "Plan")
        if !plan.feasible {
            CardBox(stroke: Theme.bad) {
                Text("**Couldn't plan the trip.** \(plan.message ?? "")").font(.subheadline)
            }
            .padding(.bottom, 12)
        }
        CardBox {
            VStack(alignment: .leading, spacing: 14) {
                StatRow(spacing: 12) {
                    StatView(label: "Distance", value: "\(plan.totalKm) km")
                    StatView(
                        label: "Trip time",
                        value: Fmt.minutes(Double(plan.driveMinutes + plan.chargeMinutes)),
                        sub: tr("of which charging \(Fmt.minutes(Double(plan.chargeMinutes)))")
                    )
                }
                StatRow(spacing: 12) {
                    StatView(label: "Arrive", value: Fmt.clock(plan.arriveAt), sub: tr("with \(plan.arriveSoc) % battery"))
                    StatView(label: "Charging cost", value: Fmt.eur(plan.costEur), sub: Fmt.stops(plan.stops.count))
                }
            }
        }

        routeMap(plan, from: from, to: to)
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.top, 12)

        VStack(alignment: .leading, spacing: 8) {
            endpoint(from.name, tr("Departure \(Fmt.clock(departure)) · \(Int(model.soc)) %"))
            ForEach(Array(plan.stops.enumerated()), id: \.element.id) { item in
                stopCard(item.element, index: item.offset + 1)
            }
            endpoint(to.name, tr("Arrival \(Fmt.clock(plan.arriveAt)) · \(plan.arriveSoc) %"))
        }
        .padding(.top, 12)
    }

    private func routeMap(_ plan: TripPlan, from: Place, to: Place) -> some View {
        let coords = [from.latLng.coordinate] + plan.stops.map(\.station.coordinate) + [to.latLng.coordinate]
        return Map(initialPosition: .automatic) {
            MapPolyline(coordinates: coords)
                .stroke(Theme.brand, lineWidth: 4)
            Marker(from.name, systemImage: "car.fill", coordinate: from.latLng.coordinate)
                .tint(Theme.brand)
            ForEach(plan.stops) { stop in
                Annotation(stop.station.name, coordinate: stop.station.coordinate) {
                    StationPin(station: stop.station, emphasized: true)
                }
            }
            Marker(to.name, systemImage: "flag.checkered", coordinate: to.latLng.coordinate)
                .tint(.black)
        }
        .id("\(from.id)-\(to.id)-\(plan.stops.map(\.id).joined())")
    }

    private func endpoint(_ title: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            Circle().fill(Theme.brand).frame(width: 12, height: 12)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(sub).font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 6)
    }

    private func stopCard(_ stop: TripStop, index: Int) -> some View {
        let op = DemoData.chargeOperator(stop.station.operatorId)
        let pColor = stop.freeProbability > 0.7 ? Theme.ok : stop.freeProbability > 0.4 ? Theme.warn : Theme.bad
        return NavigationLink(value: stop.station.id) {
            CardBox {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stop \(index) · after \(stop.distanceFromPrevKm) km · \(op.name)")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                        Text(stop.station.name).font(.headline)
                        Text("\(stop.connector.type.rawValue) · \(Int(stop.connector.powerKw)) kW")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Pill(text: tr("free \(Fmt.estimatePct(stop.freeProbability))"), color: pColor)
                }
                StatRow {
                    StatView(label: "Arrival", value: Fmt.clock(stop.arriveAt), sub: "\(stop.arriveSoc) %")
                    StatView(label: "Charge for", value: Fmt.minutes(Double(stop.chargeMinutes)), sub: tr("to \(stop.departSoc) %"))
                    StatView(label: "Cost", value: Fmt.eur(stop.costEur), sub: Fmt.kwh(stop.energyKwh))
                }
                .padding(.top, 12)
            }
        }
        .buttonStyle(.plain)
    }
}
