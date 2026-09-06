import Foundation

/// CloudKit 实现位于 AppleCloudServices.swift；该门面为 Store 和未来的单元测试提供稳定接口。
enum CloudSyncService {
    static func fetchSnapshot() async throws -> PersistedLedgerSnapshot? { try await CloudLedgerService.fetch() }
    static func push(_ snapshot: PersistedLedgerSnapshot) async throws { try await CloudLedgerService.push(snapshot) }
    static func isAvailable() async throws -> Bool { try await CloudLedgerService.accountAvailable() }
}
