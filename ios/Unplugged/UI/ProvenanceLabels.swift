import SwiftUI

// How provenance is shown to people. The model lives in Models/Provenance.swift.

extension DataClass {
    var label: String {
        switch self {
        case .demo: tr("Demo data")
        case .observed: tr("Observed data")
        case .predicted: tr("Predicted data")
        }
    }
}

extension Station {
    /// The oldest connector status: the conservative view of how current the station's status is.
    var statusProvenance: Provenance {
        connectors.map(\.provenance).min { $0.timestamp < $1.timestamp } ?? .unspecified
    }

    /// One line for the station page, e.g. "Status: Demo data, updated 14:03 · Price: Demo data".
    /// Stale status is called out explicitly instead of being shown as current.
    func provenanceSummary(at now: Date = .now) -> String {
        let status = statusProvenance
        let time = status.timestamp == .distantPast ? "–" : Fmt.clock(status.timestamp)
        let statusPart = status.isStale(at: now)
            ? tr("Status outdated (updated \(time))")
            : tr("Status: \(status.dataClass.label), updated \(time)")
        return statusPart + " · " + tr("Price: \(priceProvenance.dataClass.label)")
    }
}
