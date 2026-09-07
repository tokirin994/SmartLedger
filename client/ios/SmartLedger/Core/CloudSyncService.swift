import Foundation
import CloudKit

// 以原图为准：struct / CKContainer / accountStatus / userRecordName / fetchSnapshot / pushSnapshot 等
struct CloudSyncService {
    // 以原图为准：container / database / recordZoneID 等属性
    // 图100明确可见：import CloudKit、CKContainer、账户状态切换逻辑、获取用户记录名、fetchSnapshot()

    // 以原图为准：init(container:database:recordZoneID:)
    init(/* 以原图为准 */) {
        // 以原图为准
    }

    // MARK: - 账户状态
    // 图100明确可见：账户状态切换逻辑
    func accountStatus() async -> CKAccountStatus {
        // 以原图为准：.unknown / .available / .restricted / .noAccount / .temporarilyUnavailable
    }

    // MARK: - 用户记录名
    // 图100明确可见：获取用户记录名
    func userRecordName() async -> String {
        // 以原图为准
    }

    // MARK: - 拉取快照
    // 图100明确可见：fetchSnapshot()
    // 图101明确可见：fetchSnapshot() 异步函数、container、CKRecord、JSON 解码、错误处理
    func fetchSnapshot() async throws -> Data {
        // 以原图为准：CloudKit 查询 → CKRecord → JSONDecoder → Data
    }

    // MARK: - 推送快照
    // 图101明确可见：pushSnapshot() 异步函数、CKRecord、JSON 编码、错误处理
    func pushSnapshot(_ data: Data) async throws {
        // 以原图为准：Data → CKRecord → CloudKit 写入
    }
}
