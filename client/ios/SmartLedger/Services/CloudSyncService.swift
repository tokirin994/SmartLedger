import Foundation

/// Jianguoyun WebDAV snapshot storage. The service deliberately keeps the
/// existing sync interface so LedgerStore and persisted ledger models remain compatible.
struct CloudSyncService {
    private static let defaultEndpoint = "https://dav.jianguoyun.com/dav/SmartLedger/ledger-snapshot.json"

    private var endpoint: URL? {
        let value = UserDefaults.standard.string(forKey: "smartledger.jianguoyun.endpoint")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawValue = value.isEmpty ? Self.defaultEndpoint : value
        guard var url = URL(string: rawValue),
              url.scheme?.lowercased() == "https",
              url.host != nil else { return nil }

        // Accept either a complete snapshot URL or a WebDAV directory URL.
        // This prevents a PUT directly to a directory when users paste the
        // standard Jianguoyun DAV root from its setup page.
        if rawValue.hasSuffix("/") {
            url.appendPathComponent("ledger-snapshot.json")
        }
        return url
    }

    private var username: String {
        UserDefaults.standard.string(forKey: "smartledger.jianguoyun.username")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var password: String {
        UserDefaults.standard.string(forKey: "smartledger.jianguoyun.password") ?? ""
    }

    func accountStatus() async -> CloudAccountStatus {
        guard endpoint != nil, !username.isEmpty, !password.isEmpty else { return .noAccount }
        do {
            let (_, response) = try await perform(method: "PROPFIND", body: nil, url: directoryURL)
            guard let http = response as? HTTPURLResponse else { return .couldNotDetermine }
            switch http.statusCode {
            case 200, 204, 207: return .available
            case 401: return .noAccount
            case 403: return .restricted
            case 404: return .available // Credentials are valid; the folder is created before the first upload.
            case 500...599: return .temporarilyUnavailable
            default: return .couldNotDetermine
            }
        } catch let error as WebDAVError {
            switch error {
            case .notConfigured: return .noAccount
            case .httpStatus(401): return .noAccount
            case .httpStatus(403): return .restricted
            case .httpStatus(let code) where (500...599).contains(code): return .temporarilyUnavailable
            default: return .couldNotDetermine
            }
        } catch {
            return .couldNotDetermine
        }
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
        try await ensureDirectoryExists()
        let (_, response) = try await perform(method: "PUT", body: payload)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw WebDAVError.httpStatus(http.statusCode) }
    }

    private var directoryURL: URL? {
        endpoint?.deletingLastPathComponent()
    }

    private func ensureDirectoryExists() async throws {
        guard let directoryURL else { throw WebDAVError.notConfigured }
        let (_, response) = try await perform(method: "MKCOL", body: nil, url: directoryURL)
        guard let http = response as? HTTPURLResponse else { throw WebDAVError.invalidResponse }
        // 201 means the collection was created; 405 means it already exists.
        guard [200, 201, 204, 301, 302, 405].contains(http.statusCode) else {
            throw WebDAVError.httpStatus(http.statusCode)
        }
    }

    private func perform(method: String, body: Data?, url: URL? = nil) async throws -> (Data, URLResponse) {
        guard let requestURL = url ?? endpoint, !username.isEmpty, !password.isEmpty else { throw WebDAVError.notConfigured }
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, application/xml;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue("SmartLedger/1.0", forHTTPHeaderField: "User-Agent")
        let credential = Data("\(username):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(credential)", forHTTPHeaderField: "Authorization")
        do {
            return try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw WebDAVError.network(error.localizedDescription)
        }
    }

    enum WebDAVError: LocalizedError {
        case notConfigured, invalidResponse, network(String), httpStatus(Int)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "请先在设置中填写坚果云 WebDAV 地址、账号和应用密码"
            case .invalidResponse: return "坚果云返回了无效响应"
            case .network(let message): return "无法连接坚果云：\(message)"
            case .httpStatus(401): return "坚果云认证失败，请确认账号与应用密码（不是登录密码）"
            case .httpStatus(403): return "坚果云拒绝访问，请检查应用密码和目录权限"
            case .httpStatus(404): return "坚果云地址不存在，请填写 WebDAV 文件地址或目录地址"
            case .httpStatus(409): return "坚果云目录无法创建，请检查 WebDAV 地址是否位于 /dav/ 目录下"
            case .httpStatus(let code): return "坚果云请求失败（HTTP \(code)）"
            }
        }
    }
}
