import SwiftUI

@main
struct UnpluggedApp: App {
    @State private var model = AppModel()
    @State private var location = LocationManager()

    /// The unit-test bundle is hosted by this app. Keep launch quiet then: no
    /// notification prompt and no UI work, so tests are fast and deterministic.
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        if !Self.isRunningTests { NotificationManager.shared.setUp() }
    }

    var body: some Scene {
        WindowGroup {
            if Self.isRunningTests {
                Color.clear
            } else {
                RootView()
                    .environment(model)
                    .environment(location)
                    .environment(\.locale, model.lang.locale)
                    .id(model.lang)
                    .tint(Theme.brand)
                    .preferredColorScheme(.dark)
            }
        }
    }
}
