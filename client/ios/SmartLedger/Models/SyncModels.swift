import Foundation

enum CloudAccountStatus: String, Codable, Sendable {
    case unknown
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine

    var title: String {
        switch self {
        case .unknown: return "未知"
        case .available: return "可连接"
        case .noAccount: return "未配置或认证失败"
        case .restricted: return "访问受限"
        case .temporarilyUnavailable: return "暂不可用"
        case .couldNotDetermine: return "无法连接"
        }
    }
}

enum SyncState: String, Codable, Sendable {
    case idle
    case checking
    case syncing
    case conflict
    case success
    case failed

    var title: String {
        switch self {
        case .idle: return "空闲"
        case .checking: return "检查中"
        case .syncing: return "同步中"
        case .conflict: return "存在冲突"
        case .success: return "最近成功"
        case .failed: return "最近失败"
        }
    }
}

struct SyncConflictSummary: Codable, Sendable {
    let localUpdatedAt: Date
    let remoteUpdatedAt: Date
    let localTransactionCount: Int
    let remoteTransactionCount: Int
    let localBookCount: Int
    let remoteBookCount: Int
}

struct AppleAccountProfile: Codable, Sendable {
    let userIdentifier: String
    let fullName: String?
    let email: String?
    let authorizedAt: Date
}

struct PersistedLedgerSnapshot: Codable, Sendable {
    var categories: [LedgerCategory]
    var books: [LedgerBook]
    var transactions: [LedgerTransaction]
    var budgets: [BudgetItem]
    var nextTransactionId: Int
    var nextBookId: Int
    var nextCategoryId: Int
    var nextBudgetId: Int
    var updatedAt: Date
}
