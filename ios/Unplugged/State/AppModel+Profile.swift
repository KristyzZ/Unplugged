import Foundation

struct PointsEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    let reason: PointsReason
    let points: Int
    let at: Date
    var note: String?
}

extension AppModel {
    // MARK: Vehicle

    func setVehicle(_ id: String) {
        vehicleId = id
        save()
    }

    func setSoc(_ value: Double) {
        soc = min(100, max(1, value.rounded()))
        save()
    }

    // MARK: Points and rewards

    func addPoints(_ reason: PointsReason, note: String? = nil) {
        points += reason.points
        lifetimePoints += reason.points
        history.insert(PointsEntry(reason: reason, points: reason.points, at: .now, note: note), at: 0)
        save()
    }

    @discardableResult
    func redeem(_ reward: Points.Reward) -> Bool {
        guard points >= reward.cost else { return false }
        points -= reward.cost
        history.insert(PointsEntry(reason: .redeem, points: -reward.cost, at: .now, note: reward.title), at: 0)
        save()
        showBanner(tr("Reward activated"), reward.title)
        return true
    }

    // MARK: Payments and plans

    func setDefaultPayment(_ id: String) {
        defaultPaymentId = id
        save()
    }

    func setPlan(_ operatorId: String, active: Bool) {
        if active { activePlanIds.insert(operatorId) } else { activePlanIds.remove(operatorId) }
        save()
    }

    // MARK: Profile persistence

    private struct ProfileState: Codable {
        var vehicleId: String
        var soc: Double
        var points: Int
        var lifetimePoints: Int
        var history: [PointsEntry]
        var defaultPaymentId: String?
        var activePlanIds: [String]?
    }

    func saveProfile(to snapshot: inout PersistenceSnapshot) throws {
        try snapshot.set(ProfileState(vehicleId: vehicleId, soc: soc, points: points,
                                      lifetimePoints: lifetimePoints, history: history,
                                      defaultPaymentId: defaultPaymentId,
                                      activePlanIds: Array(activePlanIds)), for: "profile")
    }

    func loadProfile(from snapshot: PersistenceSnapshot) {
        guard let state: ProfileState = snapshot.value(for: "profile") else { return }
        vehicleId = state.vehicleId
        soc = state.soc
        points = state.points
        lifetimePoints = state.lifetimePoints
        history = state.history
        defaultPaymentId = state.defaultPaymentId ?? "visa"
        activePlanIds = Set(state.activePlanIds ?? ["ignitis"])
    }
}
