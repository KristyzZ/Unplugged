import MapKit
import SwiftUI

struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationManager.self) private var location

    @State private var path: [String] = []
    @State private var onlyFree = false
    @State private var fastOnly = false
    @State private var myCarOnly = true
    @State private var operatorId: String?
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: DemoData.vilniusCenter.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.13, longitudeDelta: 0.13)
        )
    )

    private struct Item: Identifiable {
        let station: Station
        let distance: Double
        var id: String { station.id }
    }

    private var origin: LatLng { location.location ?? DemoData.vilniusCenter }

    private var items: [Item] {
        let vehicle = model.vehicle
        return model.stations
            .filter { !onlyFree || $0.freeCount > 0 }
            .filter { !fastOnly || $0.maxPower >= 50 }
            .filter { operatorId == nil || $0.operatorId == operatorId }
            .filter { s in !myCarOnly || s.connectors.contains { Charging.isCompatible(vehicle, $0) } }
            .map { Item(station: $0, distance: Geo.haversineKm(origin, $0.latLng)) }
            .sorted { $0.distance < $1.distance }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                map
                    .frame(height: 320)
                filters
                ScrollView {
                    LazyVStack(spacing: 8) {
                        Text("\(items.count) stotelės · visų operatorių")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(items) { item in
                            NavigationLink(value: item.station.id) {
                                StationRow(station: item.station, distance: item.distance)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(Theme.background)
            .navigationTitle("Unplugged")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        OperatorScreen()
                    } label: {
                        Label("Operatoriams", systemImage: "chart.bar.xaxis")
                    }
                }
            }
            .navigationDestination(for: String.self) { id in
                StationDetailView(stationId: id)
            }
            .onAppear { location.request() }
        }
    }

    private var map: some View {
        Map(position: $camera) {
            ForEach(items) { item in
                Annotation(item.station.name, coordinate: item.station.coordinate, anchor: .center) {
                    StationPin(station: item.station)
                        .onTapGesture { path.append(item.station.id) }
                }
            }
            UserAnnotation()
        }
        .annotationTitles(.hidden)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: "Tik laisvos", active: onlyFree) { onlyFree.toggle() }
                Chip(title: "Greitos ≥ 50 kW", active: fastOnly) { fastOnly.toggle() }
                Chip(title: "Tinka mano automobiliui", active: myCarOnly) { myCarOnly.toggle() }
                ForEach(DemoData.operators) { op in
                    Chip(title: op.name, active: operatorId == op.id) {
                        operatorId = operatorId == op.id ? nil : op.id
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

struct StationPin: View {
    let station: Station
    var emphasized = false

    var body: some View {
        let size: CGFloat = emphasized ? 30 : 24
        ZStack {
            Circle().fill(station.availability.color)
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

struct StationRow: View {
    let station: Station
    var distance: Double?

    var body: some View {
        let op = DemoData.chargeOperator(station.operatorId)
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text("\(Int(station.maxPower))").font(.title3.bold())
                Text("kW").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(station.name).font(.headline).lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(op.color).frame(width: 7, height: 7)
                    Text("\(op.name) · \(station.address)").lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Pill(text: "\(station.freeCount)/\(station.workingCount) · \(station.availability.label)", color: station.availability.color)
                    Text(Fmt.price(station.pricePerKwh)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let distance {
                Text(Fmt.km(distance)).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
