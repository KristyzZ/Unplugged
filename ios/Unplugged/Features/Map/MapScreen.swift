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

    typealias Item = StationQuery.Item

    /// What the map is showing, so only nearby pins are drawn (the whole country is ~2,000 stations).
    @State private var region: StationQuery.Region?
    /// The camera moves to you once, on the first location fix, and never fights a manual pan.
    @State private var centeredOnUser = false
    @State private var userMovedCamera = false

    private var origin: LatLng { location.location ?? DemoData.vilniusCenter }

    private var items: [Item] {
        // One connector must satisfy all active filters (available + fast + fits my car).
        StationQuery.items(
            model.stations, origin: origin, vehicle: model.vehicle,
            filter: .init(onlyAvailable: onlyFree, fastOnly: fastOnly, myCarOnly: myCarOnly,
                          operatorId: operatorId, text: query))
    }

    private func priceText(_ station: Station) -> String {
        station.priceKnown ? Fmt.price(station.pricePerKwh) : tr("Price unknown")
    }

    private var dataStatusLine: String {
        switch model.feedStatus {
        case .demo: tr("Demo stations")
        case .loading: tr("Loading live data…")
        case .live(let at): tr("Live data · \(Fmt.clock(at))")
        case .offline(let from):
            from.map { tr("Offline · data from \(Fmt.clock($0))") } ?? tr("Offline · saved snapshot")
        }
    }

    private var usingFallbackOrigin: Bool { location.location == nil }

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
            .onAppear {
                // Before the intro has explained why, don't ask for location.
                if model.onboarded { location.request() }
                openRequestedStation()
            }
            // The held-spot tile asks for a station page.
            .onChange(of: model.openStationId) { openRequestedStation() }
            .onChange(of: query) { _, q in
                if !q.isEmpty { listOpen = true }
            }
        }
    }

    private func openRequestedStation() {
        guard let id = model.openStationId else { return }
        model.openStationId = nil
        path = [id]
    }

    // MARK: Map

    private func map(_ items: [Item]) -> some View {
        let pins = StationQuery.pins(items, region: region, selectedId: selectedId).shown
        return Map(position: $camera) {
            ForEach(pins) { item in
                Annotation(item.station.name, coordinate: item.station.coordinate, anchor: .bottom) {
                    StationPin(station: item.station, emphasized: item.id == selectedId)
                        .onTapGesture {
                            withMotion(.spring(duration: 0.3)) {
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
        .onMapCameraChange(frequency: .onEnd) { context in
            let r = context.region
            region = StationQuery.Region(center: LatLng(lat: r.center.latitude, lng: r.center.longitude),
                                         latSpan: r.span.latitudeDelta, lngSpan: r.span.longitudeDelta)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in userMovedCamera = true })
        .onChange(of: location.location) { _, here in
            guard let here, !centeredOnUser, !userMovedCamera else { return }
            centeredOnUser = true
            camera = .region(MKCoordinateRegion(center: here.coordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)))
        }
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
        // Search and filters float over the map; keep them from eating it at huge text sizes.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
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
                withMotion {
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
                .contentShape(Rectangle().inset(by: -14))
                .onTapGesture { withMotion(.spring(duration: 0.35)) { listOpen.toggle() } }
                .gesture(
                    DragGesture(minimumDistance: 8).onEnded { value in
                        withMotion(.spring(duration: 0.35)) {
                            if value.translation.height < -24 { listOpen = true }
                            if value.translation.height > 24 { listOpen = false }
                        }
                    }
                )
                .accessibilityLabel(listOpen ? Text("Show one station") : Text("Show all stations"))
                .accessibilityAddTraits(.isButton)

            if listOpen {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(items.count) stations nearby")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text(dataStatusLine).font(.caption).foregroundStyle(Theme.muted)
                    if usingFallbackOrigin {
                        Text("Distances are measured from Vilnius centre. Allow location to measure from where you are.")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                ScrollView {
                    LazyVStack(spacing: 8) {
                        // The nearest hundred: a list of the whole country would be slow and useless.
                        ForEach(items.prefix(100)) { item in
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
                .scaledFont(13, weight: .bold, design: .rounded, relativeTo: .footnote)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .frame(minWidth: 34, minHeight: 34)
                .background(color, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(emphasized ? 0.95 : 0), lineWidth: 2.5))
            PinTail()
                .fill(color)
                .frame(width: 12, height: 8)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .minimumTouchTarget()
        .scaleEffect(emphasized ? 1.18 : 1, anchor: .bottom)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
        .animation(Motion.pick(.spring(duration: 0.3)), value: emphasized)
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

    private var priceLabel: String { station.priceKnown ? Fmt.price(station.pricePerKwh) : tr("Price unknown") }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let op = DemoData.chargeOperator(station.operatorId)
        Group {
            if typeSize.isAccessibilitySize {
                // Large text: stack everything and let it wrap instead of truncating.
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(station.name) · \(op.name)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(station.freeCount)/\(station.workingCount) free")
                        .font(.body.weight(.medium))
                        .foregroundStyle(station.availability.color)
                    Text("\(priceLabel) · \(Fmt.km(distance))")
                        .font(.body)
                        .foregroundStyle(Theme.text)
                    Text(station.address)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
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
                        Text(priceLabel)
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
            }
        }
        .padding(16)
        .background(Theme.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct StationRow: View {
    let station: Station
    var distance: Double?

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title3) private var powerWidth: CGFloat = 48

    var body: some View {
        let op = DemoData.chargeOperator(station.operatorId)
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text("\(Int(station.maxPower))").font(.title3.bold()).foregroundStyle(Theme.text)
                Text("kW").font(.caption2).foregroundStyle(Theme.muted)
            }
            .frame(width: powerWidth)

            VStack(alignment: .leading, spacing: 3) {
                Text(station.name).font(.headline).foregroundStyle(Theme.text).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                HStack(spacing: 5) {
                    Circle().fill(op.color).frame(width: 7, height: 7)
                    Text("\(op.name) · \(station.address)").lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                }
                .font(.caption)
                .foregroundStyle(Theme.muted)
                HStack(spacing: 8) {
                    Pill(text: "\(station.freeCount)/\(station.workingCount) · \(station.availability.label)", color: station.availability.color)
                    Text(station.priceKnown ? Fmt.price(station.pricePerKwh) : tr("Price unknown")).font(.caption).foregroundStyle(Theme.muted)
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
