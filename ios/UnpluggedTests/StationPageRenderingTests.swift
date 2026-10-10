import XCTest
import SwiftUI
import UIKit
@testable import Unplugged

/// Native small-phone render evidence in the CI xcresult and test.log.
/// These frames do not replace a VoiceOver or tab-navigation interaction test.
final class StationPageRenderingTests: XCTestCase {
    @MainActor
    func testStationPageEnglishAndLithuanianAtDefaultAndAX3() async throws {
        let defaults = UserDefaults.standard
        let keys = ["unplugged.state.v1", "unplugged.state.v2", "unplugged.lang"]
        let previous = keys.map { defaults.object(forKey: $0) }
        let language = L10n.current
        keys.forEach { defaults.removeObject(forKey: $0) }
        let model = AppModel(runLoops: false, stationSource: .demo)
        model.lockScreenEnabled = false
        defer {
            model.resetDemo()
            L10n.set(language)
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        for lang in [Lang.en, .lt] {
            model.setLang(lang)
            for (label, size) in [("default", DynamicTypeSize.large), ("AX3", .accessibility3)] {
                model.session = nil
                model.holds = []
                var station = try XCTUnwrap(model.stations.first { $0.id == "akropolis" })
                station.connectors[0].status = .available
                station.connectors[0].provenance = .demo(at: .now)
                model.stations = [station]
                let host = UIHostingController(rootView: NavigationStack {
                    StationDetailView(stationId: station.id)
                }.environment(model).environment(\.locale, lang.locale)
                    .environment(\.dynamicTypeSize, size).preferredColorScheme(.dark))
                let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer { window.isHidden = true }
                await settle()
                capture(host.view, name: "station-\(lang.rawValue)-\(label)-01-unselected")
                // The existing held-spot route automatically picks this connector.
                let now = model.simNow()
                model.holds = [SpotHold(stationId: station.id, stationName: station.name,
                    connectorId: station.connectors[0].id, connectorLabel: "CCS2",
                    startedAt: now, until: now.addingTimeInterval(600), forMe: true)]
                await settle()
                capture(host.view, name: "station-\(lang.rawValue)-\(label)-02-inline-card")
                model.startCharging(at: station, connector: station.connectors[0], targetSoc: 80)
                XCTAssertTrue(model.hasActiveSession)
                XCTAssertEqual(model.tab, .charging)
                model.tab = .explore
                await settle()
                capture(host.view, name: "station-\(lang.rawValue)-\(label)-03-session-state")
            }
        }
    }

    @MainActor private func settle() async {
        try? await Task.sleep(for: .milliseconds(1000))
    }

    @MainActor private func capture(_ view: UIView, name: String) {
        view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let png = image.pngData() {
            // Accessible on Windows without Apple's xcresulttool; artifacts retain the full log.
            print("STATION_SCREENSHOT|\(name)|\(png.base64EncodedString())")
        }
    }
}
