import SwiftUI
import UIKit

/// Your chargers for rent, from Profile. With none yet, explains how hosting
/// works and starts the listing flow.
struct HostingScreen: View {
    @Environment(AppModel.self) private var model
    @State private var listing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.hostListings.isEmpty {
                    intro
                } else {
                    summary
                    ForEach(model.hostListings) { item in
                        NavigationLink { HostListingDetail(listingId: item.id) } label: { ListingRow(listing: item) }
                            .buttonStyle(.plain)
                    }
                    Button { listing = true } label: { Label("Add another charger", systemImage: "plus") }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(16)
        }
        .tabBarClearance()
        .screenBackdrop()
        .navigationTitle("Host your charger")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $listing) { ListChargerFlow() }
    }

    // MARK: No listings yet

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardBox {
                IconBadge(systemImage: "bolt.house.fill").scaleEffect(1.4).frame(width: 46, height: 46)
                Text("Earn from your charger").font(.title2.bold()).foregroundStyle(Theme.text).padding(.top, 12)
                Text("Rent out your home wallbox or your business's chargers to drivers nearby, at the times that suit you.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 4)
                Button("List your charger") { listing = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 16)
            }
            Text("How it works").font(.headline).foregroundStyle(Theme.text)
            ListCard {
                step(1, "camera.fill", "Photo and location", "Take a picture of the charger and drop a pin on the spot.")
                RowDivider()
                step(2, "chart.line.uptrend.xyaxis", "A price from the market", "We suggest one from public chargers around you. You decide.")
                RowDivider()
                step(3, "calendar.badge.checkmark", "Get booked", "Drivers find it on the map and book when it's free. Pause any time.")
            }
            Label("Only homeowners and charging station owners can list a charger.", systemImage: "checkmark.shield.fill")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }

    private func step(_ n: Int, _ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemImage: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Text(text).font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    // MARK: Listings

    private var summary: some View {
        let live = model.hostListings.filter { !$0.paused }
        let monthly = live.map { model.earnings(for: $0).payoutEur }.reduce(0, +)
        return CardBox {
            Text("Estimated monthly earnings").font(.subheadline).foregroundStyle(Theme.muted)
            Text(Fmt.eur(monthly)).scaledFont(34, weight: .bold, relativeTo: .largeTitle).foregroundStyle(Theme.ok)
            StatRow {
                StatView(label: "Listed", value: "\(model.hostListings.count)")
                StatView(label: "Taking bookings", value: "\(live.count)")
                StatView(label: "Paused", value: "\(model.hostListings.count - live.count)")
            }
            .padding(.top, 12)
        }
    }
}

/// Photo thumbnail, name, price and whether it's taking bookings.
private struct ListingRow: View {
    let listing: HostListing

    var body: some View {
        CardBox {
            HStack(spacing: 14) {
                ListingThumb(file: listing.photoFile)
                VStack(alignment: .leading, spacing: 4) {
                    Text(listing.title).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                    Text("\(listing.connector.label) · \(Fmt.kw(listing.powerKw)) · \(Fmt.price(listing.pricePerKwh))")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    ListingStatusPill(listing: listing)
                }
                Spacer(minLength: 0)
                ListRowValue(value: nil)
            }
        }
    }
}

private struct ListingThumb: View {
    let file: String?

    var body: some View {
        Group {
            if let image = HostPhotoStore.load(file) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.fill.overlay(Image(systemName: "bolt.car.fill").foregroundStyle(Theme.muted))
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Live and bookable now, live but outside its hours, or paused.
struct ListingStatusPill: View {
    let listing: HostListing

    var body: some View {
        if listing.paused {
            Pill(text: tr("Paused"), color: Theme.warn)
        } else if listing.schedule.isOpen(at: .now) {
            Pill(text: tr("Live now"), color: Theme.ok)
        } else {
            Pill(text: tr("Live · opens later"), color: Theme.info)
        }
    }
}

// MARK: - One listing

struct HostListingDetail: View {
    let listingId: String

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let listing = model.hostListings.first(where: { $0.id == listingId }) {
                content(listing)
            } else {
                ContentUnavailableView("Listing not found", systemImage: "bolt.slash")
            }
        }
        .tabBarClearance()
        .screenBackdrop()
        .navigationTitle("Your listing")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ listing: HostListing) -> some View {
        let quote = model.marketQuote(for: listing)
        let earnings = model.earnings(for: listing)
        let accepting = Binding(get: { !listing.paused }, set: { model.setListingPaused(listing.id, paused: !$0) })
        let liveOnMap = model.stations.contains { $0.id == listing.id }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ListingHero(listing: listing, photo: HostPhotoStore.load(listing.photoFile))

                ListCard {
                    ListRow(systemImage: "power", title: "Taking bookings", color: listing.paused ? Theme.warn : Theme.ok) {
                        Toggle("", isOn: accepting).labelsHidden().tint(Theme.brand)
                    }
                    if liveOnMap {
                        RowDivider()
                        Button { model.openStation(listing.id) } label: {
                            ListRow(systemImage: "map.fill", title: "See it on the map")
                        }
                        .buttonStyle(.plain)
                    }
                }

                CardBox {
                    HStack {
                        Text("This month (estimate)").font(.headline).foregroundStyle(Theme.text)
                        Spacer()
                        ListingStatusPill(listing: listing)
                    }
                    Text(Fmt.eur(listing.paused ? 0 : earnings.payoutEur))
                        .scaledFont(30, weight: .bold, relativeTo: .title)
                        .foregroundStyle(Theme.ok)
                        .padding(.top, 6)
                    StatRow {
                        StatView(label: "Bookings", value: "≈ \(listing.paused ? 0 : earnings.sessionsPerMonth)")
                        StatView(label: "Your price", value: Fmt.price(listing.pricePerKwh))
                        StatView(label: "Typical nearby", value: Fmt.price(quote.median))
                    }
                    .padding(.top, 12)
                    if abs(quote.suggested - listing.pricePerKwh) >= 0.01 {
                        Text("The market moved: we'd now suggest \(Fmt.price(quote.suggested)).")
                            .font(.caption)
                            .foregroundStyle(Theme.warn)
                            .padding(.top, 10)
                    }
                }

                ListCard {
                    info("person.fill", "Listed by", listing.kind.title)
                    RowDivider()
                    info("mappin.and.ellipse", "Location", [listing.address, listing.city].filter { !$0.isEmpty }.joined(separator: ", "))
                    RowDivider()
                    info("calendar", "Available", listing.schedule.summary)
                    RowDivider()
                    info("bolt.fill", "Booking", listing.instantBook ? tr("Instant booking") : tr("Request to book"))
                    if !listing.accessNotes.isEmpty {
                        RowDivider()
                        info("signpost.right.fill", "How to find it", listing.accessNotes)
                    }
                }

                Button { editing = true } label: { Label("Edit listing", systemImage: "pencil") }
                    .buttonStyle(SecondaryButtonStyle())
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Remove listing", systemImage: "trash").foregroundStyle(Theme.bad)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(16)
        }
        .fullScreenCover(isPresented: $editing) { ListChargerFlow(editing: listing) }
        .confirmationDialog("Remove this listing?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                dismiss()
                model.deleteListing(listing.id)
            }
        } message: {
            Text("Drivers will no longer see it. You can list it again any time.")
        }
    }

    private func info(_ icon: String, _ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(spacing: 12) {
            IconBadge(systemImage: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(Theme.muted)
                Text(value).font(.subheadline).foregroundStyle(Theme.text)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}
