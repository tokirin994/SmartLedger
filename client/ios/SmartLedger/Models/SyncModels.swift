import Foundation

/// 供 CloudKit 同步层使用的快照元数据；业务快照定义在 LedgerModels.swift。
struct LedgerSnapshotMetadata: Codable, Hashable {
    var updatedAt: Date
    var transactionCount: Int
    var bookCount: Int
}

enum SyncDecision: Hashable { case pushLocal, pullCloud, conflict }
