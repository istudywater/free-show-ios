import Foundation
import Security

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "The saved password is unavailable (Keychain status \(status)). Enter it again or try after unlocking the device." }
}

@MainActor
final class KeychainVault: CredentialVault {
    private func query(_ endpoint: FreeShowEndpoint) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "org.istudywater.FreeShowRemote.remote",
         kSecAttrAccount as String: endpoint.host.lowercased() + ":" + String(endpoint.port)]
    }
    func password(for endpoint: FreeShowEndpoint) throws -> String? {
        var query = query(endpoint)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let password = String(data: data, encoding: .utf8) else { throw KeychainError(status: status) }
        return password
    }
    func save(_ password: String, for endpoint: FreeShowEndpoint) throws {
        let query = query(endpoint)
        let values: [String: Any] = [kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
    func remove(for endpoint: FreeShowEndpoint) throws {
        let status = SecItemDelete(query(endpoint) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
