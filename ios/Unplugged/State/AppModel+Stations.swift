import Foundation
#if os(iOS)
import UIKit
#endif
import Network

/// How often the live feed is reloaded. The whole country is about 0.5 MB compressed per reload,
/// so it is slower on an expensive connection (cellular, personal hotspot).
enum StationRefresh {
    static let normal: TimeInterval = 60
    static let expensive: TimeInterval = 180

    private final class PathWatcher {
        static let shared = PathWatcher()
        private let monitor = NWPathMonitor()
        private let lock = NSLock()
        private var expensive = false
        init() {
            monitor.pathUpdateHandler = { [weak self] path in
                guard let self else { return }
                self.lock.lock(); self.expensive = path.isExpensive; self.lock.unlock()
            }
            monitor.start(queue: DispatchQueue(label: "unplugged.path"))
        }
        var isExpensive: Bool { lock.lock(); defer { lock.unlock() }; return expensive }
    }

    static func interval() -> TimeInterval { PathWatcher.shared.isExpensive ? expensive : normal }
}

extension AppModel {
    static let stationSourceKey = "unplugged.stationSource"

    static var savedStationSource: StationSource {
        UserDefaults.standard.string(forKey: stationSourceKey).flatMap(StationSource.init(rawValue:)) ?? .real
    }

    /// Shows the invented demo stations instead of the real ones (for offline demos).
    func setStationSource(_ source: StationSource) {
        guard source != stationSource else { return }
        stationSource = source
        UserDefaults.standard.set(source.rawValue, forKey: Self.stationSourceKey)
        feedStatus = source == .demo ? .demo : .loading
        refreshStations()
        if source == .real { Task { await refreshLiveStations() } }
    }

    /// The snapshot bundled with the app, so the map is never empty on first launch or offline.
    /// Its statuses are as old as the snapshot, so they read as "unknown" until live data arrives.
    func loadBundledStations() {
        guard stationSource == .real else { feedStatus = .demo; return }
        if let snapshot = FeedSnapshot.bundled() {
            baseStations = StationBuilder.stations(from: snapshot)
            tariffCache = snapshot.tariffs
            baseStationsDate = snapshot.generatedAt
        }
        feedStatus = .loading
    }

    /// Fetches the whole country from the open feed. Parsing and mapping run off the main thread.
    /// On failure the previous data stays on screen and the status says so.
    func refreshLiveStations() async {
        guard stationSource == .real, !isRefreshingStations else { return }
        isRefreshingStations = true
        defer { isRefreshingStations = false }
        do {
            var snapshot = try await feed.fetch()
            if snapshot.tariffs.isEmpty { snapshot.tariffs = tariffCache }     // a failed tariff call keeps the old prices
            let built = await Task.detached(priority: .userInitiated) {
                StationBuilder.stations(from: snapshot, observedAt: snapshot.generatedAt)
            }.value
            guard stationSource == .real else { return }
            baseStations = built
            tariffCache = snapshot.tariffs
            baseStationsDate = snapshot.generatedAt
            feedStatus = .live(at: snapshot.generatedAt)
            refreshStations()
        } catch {
            guard stationSource == .real else { return }
            feedStatus = .offline(dataFrom: baseStationsDate)
        }
    }

    /// Reload as soon as the app comes back to the foreground.
    func observeForeground() {
        #if os(iOS)
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refreshLiveStations() }
        }
        #endif
    }
}
