import Foundation

extension AppModel {
    // MARK: Listings

    /// Adds a new listing or replaces an edited one. A new photo (saved with
    /// HostPhotoStore) replaces the old file.
    func publishListing(_ listing: HostListing) {
        let previous = hostListings.first { $0.id == listing.id }
        if let old = previous?.photoFile, old != listing.photoFile { HostPhotoStore.delete(old) }
        if let i = hostListings.firstIndex(where: { $0.id == listing.id }) {
            hostListings[i] = listing
            showBanner(tr("Listing updated"), listing.title)
        } else {
            hostListings.insert(listing, at: 0)
            showBanner(tr("Your charger is live"), tr("Drivers nearby can now find and book \(listing.title)."))
        }
        save()
        refreshStations()
    }

    func setListingPaused(_ id: String, paused: Bool) {
        guard let i = hostListings.firstIndex(where: { $0.id == id }) else { return }
        hostListings[i].paused = paused
        save()
        refreshStations()
    }

    func deleteListing(_ id: String) {
        guard let i = hostListings.firstIndex(where: { $0.id == id }) else { return }
        HostPhotoStore.delete(hostListings[i].photoFile)
        hostListings.remove(at: i)
        if openStationId == id { openStationId = nil }
        save()
        refreshStations()
    }

    /// The listing behind a station on the map, if a host offers it.
    func hostListing(forStation id: String) -> HostListing? {
        hostListings.first { $0.id == id } ?? PrivateChargers.listings.first { $0.id == id }
    }

    /// Public stations only: the market a host's price is compared with.
    var publicStations: [Station] {
        stations.filter { $0.operatorId != HostListing.operatorId }
    }

    func marketQuote(for listing: HostListing) -> MarketQuote {
        Hosting.marketQuote(at: listing.location, powerKw: listing.powerKw, stations: publicStations)
    }

    func earnings(for listing: HostListing) -> HostEarnings {
        Hosting.earnings(
            schedule: listing.schedule, powerKw: listing.powerKw, spots: listing.spots, price: listing.pricePerKwh,
            quote: marketQuote(for: listing),
            nearbyOccupancy: Hosting.nearbyOccupancy(at: listing.location, stations: publicStations)
        )
    }

    // MARK: Hosting persistence

    private struct HostingState: Codable {
        var listings: [HostListing]
    }

    func saveHosting(to snapshot: inout PersistenceSnapshot) throws {
        try snapshot.set(HostingState(listings: hostListings), for: "hosting")
    }

    func loadHosting(from snapshot: PersistenceSnapshot) {
        guard let state: HostingState = snapshot.value(for: "hosting") else { return }
        hostListings = state.listings
    }
}
