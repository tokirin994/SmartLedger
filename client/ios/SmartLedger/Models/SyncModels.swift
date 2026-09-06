//
//  SyncModels.swift
//  SmartLedger
//
//  CloudKit 同步相关模型
//

import Foundation

// MARK: - CloudAccountStatus

/// iCloud 账号状态
enum CloudAccountStatus: Int, Codable, Sendable {
    case unknown = 0
    case available = 1
    case restricted = 2
    case noAccount = 3
    case temporarilyUnavailable = 4

    var title: String {
        switch self {
        case .unknown:
            return "未知"
        case .available:
            return "可用"
        case .restricted:
            return "受限"
        case .noAccount:
            return "未登录 iCloud"
        case .temporarilyUnavailable:
            return "暂时不可用"
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
        }
    }
}

// MARK: - SyncState

/// 同步状态
enum SyncState: Int, Codable, Sendable {
    case idle = 0
    case checking = 1
    case syncing = 2
    case conflict = 3
    case success = 4
    case failure = 5

    var title: String {
        switch self {
        case .idle:
            return "空闲"
        case .checking:
            return "检查中"
        case .syncing:
            return "同步中"
        case .conflict:
            return "存在冲突"
        case .success:
            return "最近成功"
        case .failure:
            return "最近失败"
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

// MARK: - SyncConflictSummary

/// 同步冲突摘要
struct SyncConflictSummary: Codable, Identifiable, Sendable {
    let id: String
    let entityType: String
    let entityId: String
    let localModifiedAt: Date
    let remoteModifiedAt: Date
    let conflictingFields: [String]
    var resolved: Bool = false

    var description: String {
        "\(entityType) 冲突：\(conflictingFields.joined(separator: ", "))"
    }
}

// MARK: - AppleAccountProfile

/// 苹果账号资料
struct AppleAccountProfile: Codable, Sendable {
    let identityToken: String?
    let authorizationCode: String?
    let userIdentifier: String?
    let fullName: PersonNameComponents?
    let email: String?
    let isRealUser: Bool
    let fetchedAt: Date

    init(identityToken: String? = nil,
         authorizationCode: String? = nil,
         userIdentifier: String? = nil,
         fullName: PersonNameComponents? = nil,
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
}

// MARK: - PersistedLedgerSnapshot

/// 持久化的账本快照（用于离线/冲突比对）
struct PersistedLedgerSnapshot: Codable, Identifiable, Sendable {
    let id: String
    let bookId: String
    let version: Int
    let recordCount: Int
    let transactionIds: [String]
    let checksum: String
    let createdAt: Date
    let updatedAt: Date?
    var dirty: Bool = false

    init(id: String = UUID().uuidString,
         bookId: String,
         version: Int = 1,
         recordCount: Int = 0,
         transactionIds: [String] = [],
         checksum: String = "",
         createdAt: Date = Date(),
         updatedAt: Date? = nil,
         dirty: Bool = false) {
        self.id = id
        self.bookId = bookId
        self.version = version
        self.recordCount = recordCount
        self.transactionIds = transactionIds
        self.checksum = checksum
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.dirty = dirty
    }
}
