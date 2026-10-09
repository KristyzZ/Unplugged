import SwiftUI

/// Background for every non-map screen (Plan, Charging, Profile and pushed
/// pages). Plain graphite, so the frosted cards and the Explore map stay the
/// only textured surfaces.
struct ScreenBackdrop: View {
    var body: some View {
        Theme.background
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    func screenBackdrop() -> some View {
        background { ScreenBackdrop() }
    }
}
