import SwiftUI
import UIKit

// Shared accessibility helpers: Reduce Motion, Dynamic Type for fixed-size
// display numerals, and minimum touch targets.

enum Motion {
    static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// The animation, or nil when Reduce Motion is on.
    static func pick(_ animation: Animation) -> Animation? { reduced ? nil : animation }
}

/// `withAnimation` that is skipped when Reduce Motion is on.
func withMotion<R>(_ animation: Animation? = .default, _ body: () throws -> R) rethrows -> R {
    try withAnimation(Motion.reduced ? nil : animation, body)
}

private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// A fixed point size that still follows the user's Dynamic Type setting.
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default,
                    relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, relativeTo: style))
    }

    /// Grows the tappable area to at least 44 × 44 pt without changing the layout.
    func minimumTouchTarget() -> some View {
        contentShape(Rectangle().inset(by: -12))
    }
}
