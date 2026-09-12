import Foundation

/// Jianguoyun WebDAV snapshot storage. The service deliberately keeps the
/// existing sync interface so LedgerStore and persisted ledger models remain compatible.
struct CloudSyncService {
    private static let defaultEndpoint = "https://dav.jianguoyun.com/dav/SmartLedger/ledger-snapshot.json"

    private var endpoint: URL? {
        let value = UserDefaults.standard.string(forKey: "smartledger.jianguoyun.endpoint")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return URL(string: value.isEmpty ? Self.defaultEndpoint : value)
    }

    private var username: String {
        UserDefaults.standard.string(forKey: "smartledger.jianguoyun.username")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var password: String {
        UserDefaults.standard.string(forKey: "smartledger.jianguoyun.password") ?? ""
    }

    func accountStatus() async -> CloudAccountStatus {
        guard endpoint != nil, !username.isEmpty, !password.isEmpty else { return .noAccount }
        return .available
    }

    func userRecordName() async -> String? {
        username.isEmpty ? nil : username
    }

    func fetchSnapshot() async throws -> PersistedLedgerSnapshot? {
        let (data, response) = try await perform(method: "GET", body: nil)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.invalidResponse }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw WebDAVError.httpStatus(http.statusCode) }
        return try JSONDecoder.iso8601.decode(PersistedLedgerSnapshot.self, from: data)
    }

    func pushSnapshot(_ snapshot: PersistedLedgerSnapshot) async throws {
        let payload = try JSONEncoder.iso8601.encode(snapshot)
        let (_, response) = try await perform(method: "PUT", body: payload)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WebDAVError.invalidResponse
        }
    }

    private func perform(method: String, body: Data?) async throws -> (Data, URLResponse) {
        guard let endpoint, !username.isEmpty, !password.isEmpty else { throw WebDAVError.notConfigured }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let credential = Data("\(username):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(credential)", forHTTPHeaderField: "Authorization")
        return try await URLSession.shared.data(for: request)
    }

    enum WebDAVError: LocalizedError {
        case notConfigured, invalidResponse, httpStatus(Int)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "请先在设置中填写坚果云 WebDAV 地址、账号和应用密码"
            case .invalidResponse: return "坚果云返回了无效响应"
            case .httpStatus(let code): return "坚果云请求失败（HTTP \(code)）"
            }
        }
    }
}