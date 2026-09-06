import AuthenticationServices
import CloudKit
import Foundation
import UIKit

@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let completion: (Result<AppleAccountProfile, Error>) -> Void
    init(completion: @escaping (Result<AppleAccountProfile, Error>) -> Void) { self.completion = completion }
    func start() { let request = ASAuthorizationAppleIDProvider().createRequest(); request.requestedScopes = [.fullName, .email]; let controller = ASAuthorizationController(authorizationRequests: [request]); controller.delegate = self; controller.presentationContextProvider = self; controller.performRequests() }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) { guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }; let displayName = [credential.fullName?.familyName, credential.fullName?.givenName].compactMap { $0 }.joined(); completion(.success(AppleAccountProfile(userIdentifier: credential.user, fullName: displayName.isEmpty ? "Apple 用户" : displayName, email: credential.email ?? "", authorizedAt: Date()))) }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) { completion(.failure(error)) }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor() }
}

enum CloudLedgerService {
    private static let recordID = CKRecord.ID(recordName: "ledgerSnapshot")
    private static let database = CKContainer.default().privateCloudDatabase
    static func accountAvailable() async throws -> Bool { try await CKContainer.default().accountStatus() == .available }
    static func fetch() async throws -> PersistedLedgerSnapshot? { do { let record = try await database.record(for: recordID); guard let data = record["snapshot"] as? Data else { return nil }; return try JSONDecoder().decode(PersistedLedgerSnapshot.self, from: data) } catch let error as CKError where error.code == .unknownItem { return nil } }
    static func push(_ snapshot: PersistedLedgerSnapshot) async throws { let record = CKRecord(recordType: "LedgerSnapshot", recordID: recordID); record["snapshot"] = try JSONEncoder().encode(snapshot) as CKRecordValue; record["updatedAt"] = snapshot.updatedAt as CKRecordValue; _ = try await database.save(record) }
}
