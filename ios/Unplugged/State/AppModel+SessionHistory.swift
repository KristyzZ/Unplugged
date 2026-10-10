import Foundation

extension AppModel {
    /// Archive on release, not on opening/dismissing the receipt. This function
    /// never awards points; the release transaction owns the one reward event.
    func archiveCompletedSession(_ s: ChargingSession) {
        guard s.endedAt != nil, !sessionHistory.contains(where: { $0.id == s.id }) else { return }
        sessionHistory.insert(s, at: 0)
        sessionHistory = Array(sessionHistory.prefix(30))
    }
}
