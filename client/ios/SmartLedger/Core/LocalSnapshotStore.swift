import Foundation

actor LocalSnapshotStore {
  private let url: URL

  init(filename: String = "ledger-snapshot.json") {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let directory = base.appendingPathComponent("SmartLedgerLocal", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    self.url = directory.appendingPathComponent(filename)
  }

  func load() throws -> PersistedLedgerSnapshot? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    return try JSONDecoder.iso8601.decode(PersistedLedgerSnapshot.self, from: data)
  }

  func save(_ snapshot: PersistedLedgerSnapshot) throws {
    let data = try JSONEncoder.iso8601.encode(snapshot)
    try data.write(to: url, options: Data.WritingOptions.atomic)
  }
}
