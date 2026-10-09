import SwiftUI

@main
struct UnpluggedApp: App {
    @State private var model = AppModel.shared
    @State private var location = LocationManager()

    init() {
        NotificationManager.shared.setUp()
    }

    var body: some Scene {
        WindowGroup {
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
