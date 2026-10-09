import MapKit
import Observation
import SwiftUI

/// A dimmed, static map of Vilnius behind every non-map screen, so Plan,
/// Charging, Profile and pushed pages share the look of the Explore tab.
/// Rendered once with MKMapSnapshotter (an image, not a live map) and shared.
@MainActor
@Observable
final class MapBackdropStore {
    static let shared = MapBackdropStore()

    private(set) var image: UIImage?
    @ObservationIgnored private var started = false

    func load(size: CGSize, scale: CGFloat) {
        guard !started, size.width > 0, size.height > 0 else { return }
        started = true

        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll

        let options = MKMapSnapshotter.Options()
        options.preferredConfiguration = configuration
        options.region = MKCoordinateRegion(
            center: DemoData.vilniusCenter.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.09)
        )
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark).modifyingTraits {
            $0.displayScale = scale
        }

        let snapshotter = MKMapSnapshotter(options: options)
        Task {
            if let snapshot = try? await snapshotter.start() {
                withAnimation(.easeOut(duration: 0.4)) { self.image = snapshot.image }
            } else {
                started = false // try again next time a screen appears
            }
        }
    }
}

struct ScreenBackdrop: View {
    var body: some View {
        let image = MapBackdropStore.shared.image
        GeometryReader { geo in
            ZStack {
                Theme.background
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blur(radius: 1.5)
                        .transition(.opacity)
                }
                // Keep text readable: darker at the top (titles) and bottom (tab bar).
                LinearGradient(
                    stops: [
                        .init(color: Theme.background.opacity(0.88), location: 0),
                        .init(color: Theme.background.opacity(0.55), location: 0.35),
                        .init(color: Theme.background.opacity(0.6), location: 0.7),
                        .init(color: Theme.background.opacity(0.9), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .onAppear {
                MapBackdropStore.shared.load(size: geo.size, scale: UITraitCollection.current.displayScale)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Dimmed Vilnius map behind the screen, matching the Explore tab.
    func screenBackdrop() -> some View {
        background { ScreenBackdrop() }
    }
}
