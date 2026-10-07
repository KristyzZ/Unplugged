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
                    Text("Suplanuosime, kur ir kiek krautis, atsižvelgiant į automobilį, maršrutą ir stotelių užimtumą.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 12)
                    form
                    if let plan, let from = plannedFrom, let to = plannedTo {
                        results(plan, from: from, to: to)
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Kelionė")
            .navigationDestination(for: String.self) { id in
                StationDetailView(stationId: id)
            }
        }
    }

    private var form: some View {
        let vehicle = model.vehicle
        let socBinding = Binding(get: { model.soc }, set: { model.setSoc($0) })
        let vehicleBinding = Binding(get: { model.vehicleId }, set: { model.setVehicle($0) })
        return CardBox {
            Text("Automobilis").font(.subheadline.weight(.medium))
            Picker("Automobilis", selection: vehicleBinding) {
                ForEach(DemoData.vehicles) { v in
                    Text("\(v.name) · \(Int(v.batteryKwh)) kWh").tag(v.id)
                }
            }
            .pickerStyle(.menu)
            .padding(.bottom, 12)

            Text("Dabartinė baterijos įkrova: \(Int(model.soc)) %").font(.subheadline.weight(.medium))
            Slider(value: socBinding, in: 5...100, step: 1)
            SocBar(value: model.soc)
            Text("≈ \(Int(vehicle.rangeKm(soc: model.soc))) km nuvažiuojamo atstumo")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .padding(.bottom, 12)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Iš").font(.subheadline.weight(.medium))
                    placePicker(selection: $originId)
                }
                VStack(alignment: .leading) {
                    Text("Į").font(.subheadline.weight(.medium))
                    placePicker(selection: $destinationId)
                }
            }

            Button("Planuoti kelionę") {
                departure = Date()
                plannedFrom = origin
                plannedTo = destination
                withAnimation {
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
        Picker("Vieta", selection: selection) {
            ForEach(DemoData.places) { p in Text(p.name).tag(p.id) }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func results(_ plan: TripPlan, from: Place, to: Place) -> some View {
        SectionHeader(title: "Planas")
        if !plan.feasible {
            CardBox(stroke: Theme.bad) {
                Text("**Kelionės suplanuoti nepavyko.** \(plan.message ?? "")").font(.subheadline)
            }
            .padding(.bottom, 12)
        }
        CardBox {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                GridRow {
                    StatView(label: "Atstumas", value: "\(plan.totalKm) km")
                    StatView(
                        label: "Kelionės laikas",
                        value: Fmt.minutes(Double(plan.driveMinutes + plan.chargeMinutes)),
                        sub: "iš jų krovimas \(Fmt.minutes(Double(plan.chargeMinutes)))"
                    )
                }
                GridRow {
                    StatView(label: "Atvyksite", value: Fmt.clock(plan.arriveAt), sub: "su \(plan.arriveSoc) % baterija")
                    StatView(label: "Įkrovimų kaina", value: Fmt.eur(plan.costEur), sub: Fmt.stops(plan.stops.count))
                }
            }
        }

        routeMap(plan, from: from, to: to)
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.top, 12)

        VStack(alignment: .leading, spacing: 8) {
            endpoint(from.name, "Išvykimas \(Fmt.clock(departure)) · \(Int(model.soc)) %")
            ForEach(Array(plan.stops.enumerated()), id: \.element.id) { item in
                stopCard(item.element, index: item.offset + 1)
            }
            endpoint(to.name, "Atvykimas \(Fmt.clock(plan.arriveAt)) · \(plan.arriveSoc) %")
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
                Text(sub).font(.caption).foregroundStyle(.secondary)
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
                        Text("\(index) sustojimas · po \(stop.distanceFromPrevKm) km · \(op.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(stop.station.name).font(.headline)
                        Text("\(stop.connector.type.rawValue) · \(Int(stop.connector.powerKw)) kW")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Pill(text: "laisva \(Fmt.pct(stop.freeProbability))", color: pColor)
                }
                HStack(alignment: .top) {
                    StatView(label: "Atvykimas", value: Fmt.clock(stop.arriveAt), sub: "\(stop.arriveSoc) %")
                    StatView(label: "Krautis", value: Fmt.minutes(Double(stop.chargeMinutes)), sub: "iki \(stop.departSoc) %")
                    StatView(label: "Kaina", value: Fmt.eur(stop.costEur), sub: String(format: "%.1f kWh", stop.energyKwh))
                }
                .padding(.top, 12)
            }
        }
        .buttonStyle(.plain)
    }
}
