import CloudKit
import Foundation

struct CloudSyncService {
  private let container = CKContainer.default()
  private let recordID = CKRecord.ID(recordName: "primary-ledger-snapshot")

  func accountStatus() async -> CloudAccountStatus {
    do {
      let status = try await container.accountStatus()
      switch status {
      case .available: return .available
      case .noAccount: return .noAccount
      case .restricted: return .restricted
      case .temporarilyUnavailable: return .temporarilyUnavailable
      case .couldNotDetermine: return .couldNotDetermine
      @unknown default: return .unknown
      }
    } catch {
      return .couldNotDetermine
    }
  }

  func userRecordName() async -> String? {
    do {
      let id = try await container.userRecordID()
      return id.recordName
    } catch {
      return nil
    }
  }

  func fetchSnapshot() async throws -> PersistedLedgerSnapshot? {
    do {
      let record = try await container.privateCloudDatabase.record(for: recordID)
      guard let payload = record["payload"] as? Data ?? (record["payload"] as? NSData).map({ Data(referencing: $0) }) else {
        return nil
      }
      return try JSONDecoder.iso8601.decode(PersistedLedgerSnapshot.self, from: payload)
    } catch let error as CKError where error.code == .unknownItem {
      return nil
    }
  }

  func pushSnapshot(_ snapshot: PersistedLedgerSnapshot) async throws {
    let record: CKRecord
    do {
      record = try await container.privateCloudDatabase.record(for: recordID)
    } catch let error as CKError where error.code == .unknownItem {
      record = CKRecord(recordType: "LedgerSnapshot", recordID: recordID)
    }

    let data = try JSONEncoder.iso8601.encode(snapshot)
    record["payload"] = data as NSData
    record["updatedAt"] = snapshot.updatedAt as NSDate
    record["source"] = "SmartLedgerLocal"
    _ = try await container.privateCloudDatabase.save(record)
  }
}
