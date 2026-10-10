import Foundation

/// An atomic snapshot of independently Codable feature payloads. Features own
/// their schemas, so adding a session/report/profile field never edits a common
/// Persisted struct. A legacy flat JSON blob can be decoded by the same feature
/// payloads because their field names match the original v1 representation.
struct PersistenceSnapshot {
    private var sections: [String: Data] = [:]
    private var legacyData: Data?

    init() {}

    init(data: Data) throws {
        sections = try JSONDecoder().decode([String: Data].self, from: data)
    }

    init(legacyData: Data) {
        self.legacyData = legacyData
    }

    mutating func set<Value: Encodable>(_ value: Value, for feature: String) throws {
        sections[feature] = try JSONEncoder().encode(value)
    }

    func value<Value: Decodable>(for feature: String) -> Value? {
        guard let data = sections[feature] ?? legacyData else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(sections)
    }
}

extension AppModel {
    // The legacy blob remains untouched. On the next normal save, write the
    // feature snapshot under v2; a failed encoding cannot partially overwrite it.
    private static let snapshotKey = "unplugged.state.v2"
    private static let legacyKey = "unplugged.state.v1"

    func save() {
        do {
            var snapshot = PersistenceSnapshot()
            try saveProfile(to: &snapshot)
            try saveSession(to: &snapshot)
            try saveQueue(to: &snapshot)
            try saveReports(to: &snapshot)
            try saveClock(to: &snapshot)
            UserDefaults.standard.set(try snapshot.encoded(), forKey: Self.snapshotKey)
        } catch {
            // Match the prototype's existing behavior: retain the last save.
        }
    }

    func load() {
        let defaults = UserDefaults.standard
        let snapshot: PersistenceSnapshot
        if let data = defaults.data(forKey: Self.snapshotKey),
           let current = try? PersistenceSnapshot(data: data) {
            snapshot = current
        } else if let data = defaults.data(forKey: Self.legacyKey) {
            snapshot = PersistenceSnapshot(legacyData: data)
        } else {
            return
        }
        loadProfile(from: snapshot)
        loadSession(from: snapshot)
        loadQueue(from: snapshot)
        loadReports(from: snapshot)
        loadClock(from: snapshot)
    }
}
