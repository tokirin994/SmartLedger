import Foundation

protocol LedgerSnapshotStore {
    func load() throws -> PersistedLedgerSnapshot?
    func save(_ snapshot: PersistedLedgerSnapshot) throws
}

struct LocalSnapshotStore: LedgerSnapshotStore {
    let key: String
    init(key: String = "smartLedger.snapshot.v1") { self.key = key }
    func load() throws -> PersistedLedgerSnapshot? { guard let data = UserDefaults.standard.data(forKey: key) else { return nil }; return try JSONDecoder().decode(PersistedLedgerSnapshot.self, from: data) }
    func save(_ snapshot: PersistedLedgerSnapshot) throws { UserDefaults.standard.set(try JSONEncoder().encode(snapshot), forKey: key) }
}
