import CoreLocation
import MapKit
import PhotosUI
import SwiftUI
import UIKit

/// Step-by-step listing of your own charger: who you are, a photo, where it
/// is, the charger, when it's free, the price (from the local market), the
/// details, then a review. Editing opens on the review with every step one tap away.
struct ListChargerFlow: View {
    enum Step: Int, CaseIterable {
        case owner, photo, location, charger, schedule, price, details, review
    }

    @Environment(AppModel.self) private var model
    @Environment(LocationManager.self) private var location
    @Environment(\.dismiss) private var dismiss

    @State private var draft: HostListing
    @State private var photo: UIImage?
    @State private var photoChanged = false
    @State private var step: Step
    @State private var ownerConfirmed: Bool
    /// The host has moved the price themselves; stop replacing it with the suggestion.
    @State private var priceTouched: Bool
    /// A step opened from the review goes straight back to it.
    @State private var backToReview = false
    @State private var confirmDiscard = false
    private let isEditing: Bool

    init(editing: HostListing? = nil) {
        _draft = State(initialValue: editing ?? HostListing())
        _photo = State(initialValue: HostPhotoStore.load(editing?.photoFile))
        _step = State(initialValue: editing == nil ? .owner : .review)
        _ownerConfirmed = State(initialValue: editing != nil)
        _priceTouched = State(initialValue: editing != nil)
        isEditing = editing != nil
    }

    private var canContinue: Bool {
        switch step {
        case .owner: ownerConfirmed
        case .photo: photo != nil
        case .location: !draft.address.trimmingCharacters(in: .whitespaces).isEmpty
        case .charger: true
        case .schedule: !draft.schedule.days.isEmpty
        case .price: true
        case .details: !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
        case .review: ownerConfirmed && photo != nil
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progress
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        stepContent
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                bottomBar
            }
            .screenBackdrop()
            .navigationTitle(isEditing ? "Edit listing" : "List your charger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { confirmDiscard = true }
                }
            }
            .confirmationDialog(isEditing ? "Discard your changes?" : "Discard this listing?",
                                isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
            }
            .onChange(of: step) { _, new in
                if new == .price && !priceTouched {
                    draft.pricePerKwh = model.marketQuote(for: draft).suggested
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Chrome

    private var progress: some View {
        let value = Double(step.rawValue + 1) / Double(Step.allCases.count)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill)
                Capsule().fill(Theme.brand).frame(width: geo.size.width * value)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(Motion.pick(.easeOut(duration: 0.3)), value: step)
        .accessibilityElement()
        .accessibilityLabel(Text("Step \(step.rawValue + 1) of \(Step.allCases.count)"))
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if step != .owner && !backToReview && step != .review {
                Button { go(to: Step(rawValue: step.rawValue - 1) ?? .owner) } label: {
                    Text("Back").font(.headline).underline().foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 8)
                .minimumTouchTarget()
            }
            Spacer(minLength: 0)
            Button(primaryTitle, action: next)
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: step == .review ? .infinity : 200)
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.background.opacity(0.95).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }

    private var primaryTitle: LocalizedStringKey {
        if step == .review { return isEditing ? "Save changes" : "Publish listing" }
        return backToReview ? "Done" : "Next"
    }

    private func go(to target: Step) {
        withMotion(.easeInOut(duration: 0.25)) { step = target }
    }

    private func next() {
        if step == .review {
            publish()
        } else if backToReview {
            backToReview = false
            go(to: .review)
        } else {
            go(to: Step(rawValue: step.rawValue + 1) ?? .review)
        }
    }

    private func edit(_ target: Step) {
        backToReview = true
        go(to: target)
    }

    private func publish() {
        var listing = draft
        listing.title = listing.title.trimmingCharacters(in: .whitespaces)
        listing.address = listing.address.trimmingCharacters(in: .whitespaces)
        listing.accessNotes = listing.accessNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if photoChanged, let photo, let file = HostPhotoStore.save(photo, id: listing.id) {
            listing.photoFile = file
        }
        model.publishListing(listing)
        dismiss()
    }

    // MARK: Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .owner: OwnerStep(kind: $draft.kind, confirmed: $ownerConfirmed)
        case .photo: PhotoStep(photo: Binding(get: { photo }, set: { photo = $0; photoChanged = true }))
        case .location: LocationStep(listing: $draft, isEditing: isEditing)
        case .charger: ChargerStep(listing: $draft)
        case .schedule: ScheduleStep(listing: $draft)
        case .price: PriceStep(listing: $draft, touched: $priceTouched)
        case .details: DetailsStep(listing: $draft)
        case .review: ReviewStep(listing: draft, photo: photo, edit: edit)
        }
    }
}

// MARK: - Step header

private struct StepTitle: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.bold()).foregroundStyle(Theme.text)
            Text(subtitle).font(.subheadline).foregroundStyle(Theme.muted)
        }
        .padding(.bottom, 4)
    }
}

private struct FieldLabel: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
    }
}

// MARK: - 1. Owner

private struct OwnerStep: View {
    @Binding var kind: HostKind
    @Binding var confirmed: Bool

    var body: some View {
        StepTitle(title: "Who's listing this charger?",
                  subtitle: "Only owners can rent out a charger on Unplugged: homeowners and owners of charging stations.")
        ForEach(HostKind.allCases) { option in
            let active = kind == option
            Button { kind = option } label: {
                CardBox(stroke: active ? Theme.brand : nil) {
                    HStack(spacing: 14) {
                        IconBadge(systemImage: option.systemImage)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.title).font(.headline).foregroundStyle(Theme.text)
                            Text(option.detail).font(.subheadline).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: active ? "largecircle.fill.circle" : "circle")
                            .font(.title3)
                            .foregroundStyle(active ? Theme.brand : Theme.muted)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(active ? .isSelected : [])
        }
        // The whole card is the checkbox: it's a statement you agree to.
        Button { confirmed.toggle() } label: {
            CardBox(stroke: confirmed ? Theme.brand : nil) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: confirmed ? "checkmark.square.fill" : "square")
                        .font(.title2)
                        .foregroundStyle(confirmed ? Theme.brand : Theme.muted)
                    Text(kind == .homeowner
                         ? "I own this home and its charger, or the owner has given me written permission to rent it out."
                         : "I own these chargers, or I'm authorized to rent them out for the business that does.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(confirmed ? .isSelected : [])
        Label("We may ask for proof, like the charger's purchase receipt or a property document, before your first payout.",
              systemImage: "checkmark.shield.fill")
            .font(.caption)
            .foregroundStyle(Theme.muted)
    }
}

// MARK: - 2. Photo

private struct PhotoStep: View {
    @Binding var photo: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        StepTitle(title: "Take a photo of your charger",
                  subtitle: "Drivers use it to find the charger when they arrive. Daylight works best.")
        Group {
            if let photo {
                // Fill a fixed frame; a bare scaledToFill image would widen the whole step.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .overlay { Image(uiImage: photo).resizable().scaledToFill() }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityElement()
                    .accessibilityLabel(Text("Photo of your charger"))
            } else if cameraAvailable {
                Button { showCamera = true } label: { placeholder }.buttonStyle(.plain)
            } else {
                PhotosPicker(selection: $photoItem, matching: .images) { placeholder }.buttonStyle(.plain)
            }
        }
        HStack(spacing: 10) {
            if cameraAvailable {
                Button { showCamera = true } label: {
                    Label(photo == nil ? tr("Take photo") : tr("Retake"), systemImage: "camera.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(cameraAvailable ? tr("Choose") : (photo == nil ? tr("Add photo") : tr("Change photo")),
                      systemImage: "photo.on.rectangle")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        ListCard {
            tip("bolt.car.fill", "The whole charger and its plug or cable")
            RowDivider()
            tip("parkingsign", "The parking space in front of it")
            RowDivider()
            tip("eye.slash.fill", "No people, licence plates or house numbers")
        }
        .padding(.top, 4)
        .onChange(of: photoItem) { _, item in
            Task {
                let data = try? await item?.loadTransferable(type: Data.self)
                if let image = data.flatMap(UIImage.init(data:)) { photo = image }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { photo = $0 }.ignoresSafeArea()
        }
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.fill").font(.largeTitle).foregroundStyle(Theme.brand)
            Text("Add a photo").font(.headline).foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .background(Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
        }
    }

    private func tip(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemImage: icon, color: Theme.ok)
            Text(text).font(.subheadline).foregroundStyle(Theme.text)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - 3. Location

private struct LocationStep: View {
    @Binding var listing: HostListing
    let isEditing: Bool

    @Environment(LocationManager.self) private var location
    @State private var camera: MapCameraPosition = .automatic
    @State private var lookingUp = false
    @State private var placedOnce = false
    @State private var lookup: Task<Void, Never>?

    var body: some View {
        StepTitle(title: "Where is your charger?",
                  subtitle: "Move the map so the pin sits on the parking spot. Drivers see this pin on the map.")
        ZStack {
            Map(position: $camera) { UserAnnotation() }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .onMapCameraChange(frequency: .onEnd) { context in
                    let c = context.region.center
                    listing.location = LatLng(lat: c.latitude, lng: c.longitude)
                    if placedOnce { lookUpAddress() }
                    placedOnce = true
                }
            Image(systemName: "mappin")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.brand)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                .offset(y: -17)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Button {
                location.request()
                if let here = location.location { move(to: here) }
            } label: {
                Label("Use my location", systemImage: "location.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .glass(in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(10)
        }

        HStack {
            FieldLabel("Address")
            if lookingUp { ProgressView().controlSize(.small).padding(.leading, 4) }
        }
        TextField("Street and number", text: $listing.address)
            .textContentType(.fullStreetAddress)
            .padding(12)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        FieldLabel("City")
        TextField("Vilnius", text: $listing.city)
            .textContentType(.addressCity)
            .padding(12)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            camera = .region(MKCoordinateRegion(center: listing.location.coordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)))
            // A new listing starts where you are.
            if !isEditing && listing.address.isEmpty {
                location.request()
                if let here = location.location { move(to: here) }
            }
        }
        .onChange(of: location.location) { _, here in
            if let here, !isEditing && listing.address.isEmpty { move(to: here) }
        }
    }

    private func move(to point: LatLng) {
        withMotion(.easeInOut(duration: 0.4)) {
            camera = .region(MKCoordinateRegion(center: point.coordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)))
        }
        listing.location = point
        lookUpAddress()
    }

    /// Fills the address from the pin. Needs a network connection; the fields
    /// stay editable either way.
    private func lookUpAddress() {
        lookup?.cancel()
        let point = listing.location
        lookup = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            lookingUp = true
            defer { lookingUp = false }
            let placemark = try? await CLGeocoder()
                .reverseGeocodeLocation(CLLocation(latitude: point.lat, longitude: point.lng), preferredLocale: L10n.locale)
                .first
            guard !Task.isCancelled, let placemark else { return }
            let street = [placemark.thoroughfare, placemark.subThoroughfare].compactMap { $0 }.joined(separator: " ")
            if !street.isEmpty { listing.address = street }
            if let city = placemark.locality { listing.city = city }
        }
    }
}

// MARK: - 4. Charger

private struct ChargerStep: View {
    @Binding var listing: HostListing

    private var powers: [Double] {
        Hosting.powerOptions.filter { Hosting.isFast($0) == listing.connector.isDC }
    }

    private var maxSpots: Int { listing.kind == .homeowner ? 2 : 20 }

    var body: some View {
        StepTitle(title: "Tell drivers about your charger",
                  subtitle: "We only show it to drivers whose car can use it.")
        CardBox {
            FieldLabel("Plug")
            FlowChips(options: ConnectorType.allCases, selected: { $0 == listing.connector }, title: \.label) { type in
                listing.connector = type
                if Hosting.isFast(listing.powerKw) != type.isDC {
                    listing.powerKw = type.isDC ? 50 : 11
                }
            }
            .padding(.top, 8)

            FieldLabel("Power").padding(.top, 16)
            FlowChips(options: powers, selected: { $0 == listing.powerKw }, title: { Fmt.kw($0) }) { listing.powerKw = $0 }
                .padding(.top, 8)
            Text(listing.connector.isDC
                 ? "DC fast charging. Most cars add 200 km in about 30 minutes."
                 : "AC charging. Most cars take up to 11 kW, so 11 kW and 22 kW charge at the same speed for them.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .padding(.top, 8)

            Divider().padding(.vertical, 14)
            Stepper(value: $listing.spots, in: 1...maxSpots) {
                VStack(alignment: .leading, spacing: 2) {
                    FieldLabel("Chargers at this place")
                    Text("\(listing.spots)").font(.title3.bold()).foregroundStyle(Theme.text)
                }
            }
        }
        .onAppear { listing.spots = min(listing.spots, maxSpots) }
    }
}

/// Wrapping row of chips for a small set of choices.
private struct FlowChips<Option: Hashable>: View {
    let options: [Option]
    let selected: (Option) -> Bool
    let title: (Option) -> String
    let pick: (Option) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Chip(title: title(option), active: selected(option)) { pick(option) }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

// MARK: - 5. Schedule

private struct ScheduleStep: View {
    @Binding var listing: HostListing

    private var allDay: Binding<Bool> {
        Binding(get: { listing.schedule.isAllDay }, set: { on in
            if on {
                listing.schedule.fromHour = 0
                listing.schedule.toHour = 24
            } else {
                listing.schedule.fromHour = 18
                listing.schedule.toHour = 8
            }
        })
    }

    var body: some View {
        StepTitle(title: "When can drivers book it?",
                  subtitle: "Pick the times you don't need the charger yourself. You can pause bookings any time.")
        FlowChips(options: Preset.allCases, selected: { $0.schedule == listing.schedule }, title: \.title) {
            listing.schedule = $0.schedule
        }
        CardBox {
            FieldLabel("Days")
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { day in
                    let on = listing.schedule.days.contains(day)
                    Button {
                        if on { listing.schedule.days.remove(day) } else { listing.schedule.days.insert(day) }
                    } label: {
                        Text(HostSchedule.weekdaySymbols[day - 1].prefix(2))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(on ? Theme.ink : Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(on ? Theme.brand : Theme.fill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(HostSchedule.weekdaySymbols[day - 1]))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.top, 8)

            Divider().padding(.vertical, 14)
            Toggle(isOn: allDay) { FieldLabel("All day") }.tint(Theme.brand)
            if !listing.schedule.isAllDay {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Starts").font(.caption).foregroundStyle(Theme.muted)
                        DropdownField(selection: $listing.schedule.fromHour,
                                      options: (0..<24).map { ($0, Fmt.hour($0)) })
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ends").font(.caption).foregroundStyle(Theme.muted)
                        DropdownField(selection: $listing.schedule.toHour,
                                      options: (1...24).map { ($0, Fmt.hour($0 % 24)) })
                    }
                }
                .padding(.top, 12)
            }
            Text("\(listing.schedule.summary) · \(listing.schedule.hoursPerWeek) h a week")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .padding(.top, 12)
        }
        CardBox {
            Toggle(isOn: $listing.instantBook) {
                VStack(alignment: .leading, spacing: 3) {
                    FieldLabel("Instant booking")
                    Text("Drivers book straight away. Off: you accept each request within 30 minutes.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.brand)
        }
    }

    enum Preset: CaseIterable {
        case evenings, workdays, always

        var schedule: HostSchedule {
            switch self {
            case .evenings: .evenings
            case .workdays: .workdays
            case .always: .always
            }
        }

        var title: String {
            switch self {
            case .evenings: tr("Evenings and nights")
            case .workdays: tr("Working hours")
            case .always: tr("Always")
            }
        }
    }
}

// MARK: - 6. Price

private struct PriceStep: View {
    @Binding var listing: HostListing
    @Binding var touched: Bool

    @Environment(AppModel.self) private var model

    private var price: Binding<Double> {
        Binding(get: { listing.pricePerKwh }, set: {
            listing.pricePerKwh = Hosting.clampPrice(($0 * 100).rounded() / 100)
            touched = true
        })
    }

    var body: some View {
        let quote = model.marketQuote(for: listing)
        let earnings = model.earnings(for: listing)
        StepTitle(title: "Set your price",
                  subtitle: "We compare it with public chargers around yours, using today's prices.")

        CardBox {
            HStack(spacing: 16) {
                stepButton("minus", by: -0.01)
                VStack(spacing: 2) {
                    Text(String(format: "%.2f €", listing.pricePerKwh))
                        .scaledFont(40, weight: .bold, relativeTo: .largeTitle)
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                    Text("per kWh").font(.caption).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                stepButton("plus", by: 0.01)
            }
            Slider(value: price, in: Hosting.minPrice...Hosting.maxPrice, step: 0.01)
                .tint(Theme.brand)
                .padding(.top, 12)
                .accessibilityLabel(Text("Price per kWh"))
            positionNote(quote)
                .padding(.top, 6)
        }

        marketCard(quote)

        CardBox {
            Text("Estimated monthly earnings").font(.headline).foregroundStyle(Theme.text)
            Text(Fmt.eur(earnings.payoutEur))
                .scaledFont(30, weight: .bold, relativeTo: .title)
                .foregroundStyle(Theme.ok)
                .padding(.top, 6)
                .contentTransition(.numericText())
            StatRow {
                StatView(label: "Bookings", value: "≈ \(earnings.sessionsPerMonth)")
                StatView(label: "Energy sold", value: "\(Int(earnings.kwhPerMonth.rounded())) kWh")
                StatView(label: "After electricity", value: Fmt.eur(earnings.profitEur))
            }
            .padding(.top, 12)
            Text("After the \(Int(Hosting.serviceFee * 100)) % Unplugged service fee. \"After electricity\" assumes you pay \(String(format: "%.2f", Hosting.homeEnergyCost)) €/kWh. Estimate only.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .padding(.top, 10)
        }
        .animation(Motion.pick(.easeOut(duration: 0.2)), value: listing.pricePerKwh)
    }

    private func stepButton(_ icon: String, by delta: Double) -> some View {
        Button { price.wrappedValue = listing.pricePerKwh + delta } label: {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .glass(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(delta < 0 ? "Lower price" : "Raise price"))
    }

    @ViewBuilder
    private func positionNote(_ quote: MarketQuote) -> some View {
        let (text, color): (String, Color) = switch Hosting.position(of: listing.pricePerKwh, in: quote) {
        case .below: (tr("Below the market: you'll get booked more often."), Theme.ok)
        case .inLine: (tr("In line with the market."), Theme.text)
        case .above: (tr("Above the market: expect fewer bookings."), Theme.warn)
        }
        Text(text).font(.subheadline.weight(.medium)).foregroundStyle(color)
    }

    private func marketCard(_ quote: MarketQuote) -> some View {
        CardBox {
            HStack {
                Text("Market price nearby").font(.headline).foregroundStyle(Theme.text)
                Spacer()
                Pill(text: Hosting.isFast(listing.powerKw) ? tr("DC fast") : tr("AC"), color: Theme.info)
            }
            MarketRangeBar(quote: quote, price: listing.pricePerKwh)
                .padding(.top, 14)
            HStack {
                StatView(label: "Lowest", value: Fmt.price(quote.low))
                StatView(label: "Typical", value: Fmt.price(quote.median))
                StatView(label: "Highest", value: Fmt.price(quote.high))
            }
            .padding(.top, 12)
            Text(quote.sampleCount == 0
                 ? tr("No public chargers to compare with yet; using a typical Lithuanian price.")
                 : tr("From \(quote.sampleCount) public chargers within \(Fmt.km(quote.radiusKm)), updated live."))
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .padding(.top, 10)
            Divider().padding(.vertical, 12)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggested").font(.caption).foregroundStyle(Theme.muted)
                    Text(Fmt.price(quote.suggested)).font(.headline).foregroundStyle(Theme.text)
                }
                Spacer()
                Button("Use suggested") { price.wrappedValue = quote.suggested }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.brand, in: Capsule())
                    .disabled(abs(quote.suggested - listing.pricePerKwh) < 0.001)
                    .opacity(abs(quote.suggested - listing.pricePerKwh) < 0.001 ? 0.5 : 1)
            }
            Text(Hosting.isFast(listing.powerKw)
                 ? "A little under the typical price, so drivers pick you over a public charger."
                 : "A tenth under the typical price: home chargers book best when they're the cheaper choice.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .padding(.top, 6)
        }
    }
}

/// Lowest to highest market price, the typical one marked, and yours as a dot.
private struct MarketRangeBar: View {
    let quote: MarketQuote
    let price: Double

    var body: some View {
        let lo = min(quote.low, price) - 0.02
        let hi = max(quote.high, price) + 0.02
        let x = { (v: Double, w: CGFloat) in CGFloat((v - lo) / max(hi - lo, 0.01)) * w }
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fill).frame(height: 8)
                Capsule().fill(Theme.info.opacity(0.45))
                    .frame(width: max(8, x(quote.high, w) - x(quote.low, w)), height: 8)
                    .offset(x: x(quote.low, w))
                Rectangle().fill(Theme.text).frame(width: 2, height: 16)
                    .offset(x: x(quote.median, w) - 1)
                Circle().fill(Theme.brand)
                    .overlay(Circle().stroke(Theme.text, lineWidth: 2))
                    .frame(width: 18, height: 18)
                    .offset(x: x(price, w) - 9)
            }
            .frame(height: 20)
        }
        .frame(height: 20)
        .animation(Motion.pick(.easeOut(duration: 0.2)), value: price)
        .accessibilityElement()
        .accessibilityLabel(Text("Your price \(Fmt.price(price)), typical \(Fmt.price(quote.median))"))
    }
}

// MARK: - 7. Details

private struct DetailsStep: View {
    @Binding var listing: HostListing

    var body: some View {
        StepTitle(title: "Finish your listing",
                  subtitle: "A clear name and directions mean fewer calls from drivers.")
        CardBox {
            FieldLabel("Listing name")
            TextField(listing.kind == .homeowner ? "Driveway wallbox in Žvėrynas" : "Hotel car park, level -1", text: $listing.title)
                .padding(12)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 6)
            FieldLabel("How to find it (optional)").padding(.top, 14)
            TextField("Gate code is sent after booking. Park on the left.", text: $listing.accessNotes, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 6)
        }
        Text("What's there").font(.headline).foregroundStyle(Theme.text).padding(.top, 4)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(HostAmenity.allCases) { amenity in
                let on = listing.amenities.contains(amenity)
                Button {
                    if on { listing.amenities.remove(amenity) } else { listing.amenities.insert(amenity) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: amenity.systemImage).frame(width: 22)
                        Text(amenity.title).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(on ? Theme.text : Theme.muted)
                    .padding(12)
                    .background(Theme.card.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(on ? Theme.brand : Color.white.opacity(0.08), lineWidth: on ? 1.5 : 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

// MARK: - 8. Review

private struct ReviewStep: View {
    let listing: HostListing
    let photo: UIImage?
    let edit: (ListChargerFlow.Step) -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        let earnings = model.earnings(for: listing)
        StepTitle(title: "Check and publish", subtitle: "This is how drivers will see your charger.")
        ListingHero(listing: listing, photo: photo)
        ListCard {
            row(.owner, "person.fill", "Listed by", listing.kind.title)
            RowDivider()
            row(.photo, "camera.fill", "Photo", photo == nil ? tr("Missing") : tr("Added"))
            RowDivider()
            row(.location, "mappin.and.ellipse", "Location", [listing.address, listing.city].filter { !$0.isEmpty }.joined(separator: ", "))
            RowDivider()
            row(.charger, "bolt.fill", "Charger", "\(listing.connector.label) · \(Fmt.kw(listing.powerKw)) · ×\(listing.spots)")
            RowDivider()
            row(.schedule, "calendar", "Available", listing.schedule.summary)
            RowDivider()
            row(.price, "eurosign.circle.fill", "Price", Fmt.price(listing.pricePerKwh))
            RowDivider()
            row(.details, "text.alignleft", "Details",
                listing.amenities.isEmpty ? tr("No extras") : listing.amenities.sorted { $0.rawValue < $1.rawValue }.map(\.title).joined(separator: ", "))
        }
        CardBox {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated monthly earnings").font(.subheadline).foregroundStyle(Theme.muted)
                    Text(Fmt.eur(earnings.payoutEur)).font(.title2.bold()).foregroundStyle(Theme.ok)
                }
                Spacer()
                Pill(text: listing.instantBook ? tr("Instant booking") : tr("Request to book"), color: Theme.info)
            }
        }
        Text("By publishing you confirm you own this charger or may rent it out. Demo only: no real bookings or payouts are made.")
            .font(.caption)
            .foregroundStyle(Theme.muted)
    }

    private func row(_ step: ListChargerFlow.Step, _ icon: String, _ title: LocalizedStringKey, _ value: String) -> some View {
        Button { edit(step) } label: {
            HStack(spacing: 12) {
                IconBadge(systemImage: icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(Theme.muted)
                    Text(value).font(.subheadline).foregroundStyle(Theme.text).lineLimit(2)
                }
                Spacer(minLength: 8)
                Text("Edit").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.brand)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The listing's photo with its name and price on top, as drivers see it.
struct ListingHero: View {
    let listing: HostListing
    let photo: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .overlay {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        LinearGradient(colors: [Theme.brand.opacity(0.5), Theme.card], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .overlay(Image(systemName: "bolt.car.fill").font(.system(size: 48)).foregroundStyle(Theme.text.opacity(0.6)))
                    }
                }
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(listing.title.isEmpty ? tr("Your charger") : listing.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("\(listing.connector.label) · \(Fmt.kw(listing.powerKw)) · \(Fmt.price(listing.pricePerKwh))")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(16)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
