import Foundation

struct QueueEntry: Codable, Equatable {
    let stationId: String
    let joinedAt: Date
    var position: Int
}

extension AppModel {
    func joinQueue(_ station: Station) {
        queue = QueueEntry(stationId: station.id, joinedAt: .now, position: 2)
        save()
        showBanner(tr("You joined the queue"), tr("\(station.name): we'll notify you when a spot frees up."))
    }

    func leaveQueue() {
        queue = nil
        save()
    }

    // MARK: Queue persistence

    private struct QueueState: Codable {
        var queue: QueueEntry?
    }

    func saveQueue(to snapshot: inout PersistenceSnapshot) throws {
        try snapshot.set(QueueState(queue: queue), for: "queue")
    }

    func loadQueue(from snapshot: PersistenceSnapshot) {
        guard let state: QueueState = snapshot.value(for: "queue") else { return }
        queue = state.queue
    }
}
