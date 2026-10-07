import SwiftUI

@main
struct UnpluggedApp: App {
    @State private var model = AppModel()
    @State private var location = LocationManager()

    init() {
        NotificationManager.shared.setUp()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(location)
                .tint(Theme.brand)
        }
    }
}
