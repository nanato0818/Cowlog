import Foundation
import Security

enum APIError: LocalizedError {
    case invalidURL, insecureURL, missingToken, badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "接続先URLを確認してください"
        case .insecureURL: return "HTTPSの接続先を指定してください"
        case .missingToken: return "閲覧用トークンを設定してください"
        case .badResponse(let code): return "サーバーが応答できませんでした（\(code)）"
        }
    }
}

enum ReadTokenStore {
    private static let account = "cowlog-read-token"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary,
                                         [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound { return false }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

struct APIClient {
    let baseURL: String
    let token: String

    private func request<T: Decodable>(_ path: String) async throws -> T {
        let normalized = baseURL.hasSuffix("/") ? baseURL : baseURL + "/"
        guard let root = URL(string: normalized), root.scheme != nil,
              root.host != nil else {
            throw APIError.invalidURL
        }
        guard root.scheme?.lowercased() == "https" else {
            throw APIError.insecureURL
        }
        guard !token.isEmpty else { throw APIError.missingToken }
        guard let url = URL(string: path, relativeTo: root)?.absoluteURL else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw APIError.badResponse(0)
        }
        guard response.statusCode == 200 else {
            throw APIError.badResponse(response.statusCode)
        }
        return try JSONCoding.decoder().decode(T.self, from: data)
    }

    func dashboard() async throws -> Dashboard {
        try await request("v1/dashboard")
    }

    func history(cowId: String, date: String) async throws -> CowHistory {
        let allowedId = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard let safeId = cowId.addingPercentEncoding(withAllowedCharacters: allowedId),
              let safeDate = date.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { throw APIError.invalidURL }
        return try await request("v1/cows/\(safeId)/history?date=\(safeDate)")
    }
}
