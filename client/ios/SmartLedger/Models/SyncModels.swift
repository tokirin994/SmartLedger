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
        case .available: return "可用"
        case .noAccount: return "未登录 iCloud"
        case .restricted: return "受限制"
        case .temporarilyUnavailable: return "暂不可用"
        case .couldNotDetermine: return "无法判断"
        }
    }

    var description: String {
        switch self {
        case .unknown:
            return "未知"
        case .available:
            return "可用"
        case .restricted:
            return "账号受限，无法使用 iCloud 同步"
        case .noAccount:
            return "未登录 iCloud"
        case .temporarilyUnavailable:
            return "检查中"
        case .couldNotDetermine:
            return "无法判断"
        }
    }
}

//// MARK: - SyncState
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

    var isActive: Bool {
        switch self {
        case .checking, .syncing:
            return true
        default:
            return false
        }
    }
}

//// MARK: - SyncConflictSummary
struct SyncConflictSummary: Codable, Sendable {
    let localUpdatedAt: Date
    let remoteUpdatedAt: Date
    let localTransactionCount: Int
    let remoteTransactionCount: Int
    let localBookCount: Int
    let remoteBookCount: Int
}

//// MARK: - AppleAccountProfile
struct AppleAccountProfile: Codable, Sendable {
    let identityToken: String?
    let authorizationCode: String?
    let userIdentifier: String
    let fullName: String?
    let email: String?
    let isRealUser: Bool
    let fetchedAt: Date

    init(identityToken: String? = nil,
         authorizationCode: String? = nil,
         userIdentifier: String,
         fullName: String? = nil,
         email: String? = nil,
         isRealUser: Bool = false,
         fetchedAt: Date = Date()) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.userIdentifier = userIdentifier
        self.fullName = fullName
        self.email = email
        self.isRealUser = isRealUser
        self.fetchedAt = fetchedAt
    }
    let authorized: Date
}

//// MARK: - PersistedLedgerSnapshot
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

