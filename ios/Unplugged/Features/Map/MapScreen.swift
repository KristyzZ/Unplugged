import MapKit
import SwiftUI

struct MapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationManager.self) private var location

    @State private var path: [String] = []
    @State private var query = ""
    @State private var onlyFree = false
    @State private var fastOnly = false
    @State private var myCarOnly = true
    @State private var operatorId: String?
    @State private var selectedId: String?
    @State private var listOpen = false
    @FocusState private var searchFocused: Bool
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: DemoData.vilniusCenter.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.11, longitudeDelta: 0.11)
        )
    )

    struct Item: Identifiable {
        let station: Station
        let distance: Double
        var id: String { station.id }
    }

    private var origin: LatLng { location.location ?? DemoData.vilniusCenter }

    private var items: [Item] {
        let vehicle = model.vehicle
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return model.stations
            .filter { !onlyFree || $0.freeCount > 0 }
            .filter { !fastOnly || $0.maxPower >= 50 }
            .filter { operatorId == nil || $0.operatorId == operatorId }
            .filter { s in !myCarOnly || s.connectors.contains { Charging.isCompatible(vehicle, $0) } }
            .filter { s in q.isEmpty || "\(s.name) \(s.address) \(s.city)".lowercased().contains(q) }
            .map { Item(station: $0, distance: Geo.haversineKm(origin, $0.latLng)) }
            .sorted { $0.distance < $1.distance }
    }

    /// The station shown in the bottom card: the one tapped on the map, else the nearest.
    private func focused(in items: [Item]) -> Item? {
        items.first { $0.id == selectedId } ?? items.first
    }

    var body: some View {
        let items = self.items
        NavigationStack(path: $path) {
            ZStack {
                map(items).ignoresSafeArea()
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 12)
                    locateButton
                    bottomPanel(items)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 76)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { id in
                StationDetailView(stationId: id)
            }
            .onAppear { location.request() }
            .onChange(of: query) { _, q in
                if !q.isEmpty { listOpen = true }
            }
        }
    }

    // MARK: Map

    private func map(_ items: [Item]) -> some View {
        Map(position: $camera) {
            ForEach(items) { item in
                Annotation(item.station.name, coordinate: item.station.coordinate, anchor: .bottom) {
                    StationPin(station: item.station, emphasized: item.id == selectedId)
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.3)) {
                                selectedId = item.id
                                listOpen = false
                            }
                        }
                }
                .annotationTitles(.hidden)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .onTapGesture { searchFocused = false }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .top, spacing: 10) {
            ChargingTile(style: .square)
            VStack(alignment: .leading, spacing: 10) {
                searchField
                filters
            }
        }
        .padding(.top, 4)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.muted)
            TextField("Where to charge?", text: $query)
                .font(.body)
                .foregroundStyle(Theme.text)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .glass(in: Capsule())
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: "Available only", active: onlyFree) { onlyFree.toggle() }
                Chip(title: "Fast ≥ 50 kW", active: fastOnly) { fastOnly.toggle() }
                Chip(title: "Fits my car", active: myCarOnly) { myCarOnly.toggle() }
                ForEach(DemoData.operators) { op in
                    Chip(title: op.name, active: operatorId == op.id) {
                        operatorId = operatorId == op.id ? nil : op.id
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private var locateButton: some View {
        HStack {
            Spacer()
            Button {
                location.request()
                withAnimation {
                    camera = .userLocation(fallback: .region(MKCoordinateRegion(
                        center: origin.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    )))
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 48, height: 48)
                    .glass(in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Show my location"))
        }
        .padding(.bottom, 10)
    }

    // MARK: Bottom panel

    private func bottomPanel(_ items: [Item]) -> some View {
        VStack(spacing: 10) {
            // Grab handle: drag up for the full list, down for one station.
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.spring(duration: 0.35)) { listOpen.toggle() } }
                .gesture(
                    DragGesture(minimumDistance: 8).onEnded { value in
                        withAnimation(.spring(duration: 0.35)) {
                            if value.translation.height < -24 { listOpen = true }
                            if value.translation.height > 24 { listOpen = false }
                        }
                    }
                )
                .accessibilityLabel(listOpen ? Text("Show one station") : Text("Show all stations"))
                .accessibilityAddTraits(.isButton)

            if listOpen {
                HStack {
                    Text("\(items.count) stations nearby")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                }
                .padding(.horizontal, 6)
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { item in
                            NavigationLink(value: item.station.id) {
                                StationRow(station: item.station, distance: item.distance)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 340)
                .scrollIndicators(.hidden)
            } else if let item = focused(in: items) {
                NavigationLink(value: item.station.id) {
                    StationSummaryCard(station: item.station, distance: item.distance)
                }
                .buttonStyle(.plain)
            } else {
                Text("No stations match these filters.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .glass(in: RoundedRectangle(cornerRadius: 30, style: .continuous), interactive: false)
    }
}

// MARK: - Pins & rows

/// Teardrop map pin with the station's max power, colored by availability.
struct StationPin: View {
    let station: Station
    var emphasized = false

    var body: some View {
        let color = station.availability.color
        VStack(spacing: -1) {
            Text("\(Int(station.maxPower))")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 6)
                .frame(minWidth: 34, minHeight: 34)
                .background(color, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(emphasized ? 0.95 : 0), lineWidth: 2.5))
            PinTail()
                .fill(color)
                .frame(width: 12, height: 8)
        }
        .scaleEffect(emphasized ? 1.18 : 1, anchor: .bottom)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
        .animation(.spring(duration: 0.3), value: emphasized)
        .accessibilityElement()
        .accessibilityLabel(Text("\(station.name), \(Int(station.maxPower)) kW, \(station.availability.label)"))
        .accessibilityAddTraits(.isButton)
    }
}

private struct PinTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The single station card in the collapsed bottom panel.
struct StationSummaryCard: View {
    let station: Station
    let distance: Double

    var body: some View {
        let op = DemoData.chargeOperator(station.operatorId)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(station.name) · \(op.name)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(station.freeCount)/\(station.workingCount) free")
                    .font(.body.weight(.medium))
                    .foregroundStyle(station.availability.color)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Fmt.price(station.pricePerKwh))
                    .font(.body)
                    .foregroundStyle(Theme.text)
                Text(Fmt.km(distance))
                    .font(.body)
                    .foregroundStyle(Theme.text)
                Text(station.address)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .background(Theme.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct StationRow: View {
    let station: Station
    var distance: Double?

    var body: some View {
        let op = DemoData.chargeOperator(station.operatorId)
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text("\(Int(station.maxPower))").font(.title3.bold()).foregroundStyle(Theme.text)
                Text("kW").font(.caption2).foregroundStyle(Theme.muted)
            }
            .frame(width: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(station.name).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(op.color).frame(width: 7, height: 7)
                    Text("\(op.name) · \(station.address)").lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
                HStack(spacing: 8) {
                    Pill(text: "\(station.freeCount)/\(station.workingCount) · \(station.availability.label)", color: station.availability.color)
                    Text(Fmt.price(station.pricePerKwh)).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
            if let distance {
                Text(Fmt.km(distance)).font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted)
            }
        }
        .padding(12)
        .background(Theme.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
