import Foundation
import Security

struct KeychainOperations {
    let update: (CFDictionary, CFDictionary) -> OSStatus
    let add: (CFDictionary) -> OSStatus
    let read: (CFDictionary) -> (OSStatus, Data?)
    static let system = KeychainOperations(
        update: { SecItemUpdate($0, $1) },
        add: { SecItemAdd($0, nil) },
        read: { query in
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query, &item)
            return (status, item as? Data)
        }
    )
}

public struct TokenVault {
    // Dedicated app namespace. Tokens never enter UserDefaults, drafts or diagnostics.
    private let service = "dev.herdr.mobile.firstslice.pairing.v1"
    private let operations: KeychainOperations
    public init() { operations = .system }
    init(operations: KeychainOperations) { self.operations = operations }
    public func save(_ token: String, endpoint: Endpoint) throws {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: endpoint.identity]
        let values: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = operations.update(base as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            let added = operations.add(base.merging(values) { _, value in value } as CFDictionary)
            guard added == errSecSuccess else { throw VaultError.unavailable(added) }
        } else if status != errSecSuccess { throw VaultError.unavailable(status) }
    }
    public func load(endpoint: Endpoint) throws -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: endpoint.identity, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        let (status, storedData) = operations.read(query as CFDictionary)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = storedData, let value = String(data: data, encoding: .utf8) else { throw VaultError.unavailable(status) }
        return value
    }
}
public enum VaultError: Error, LocalizedError {
    case unavailable(OSStatus)
    public var errorDescription: String? { "Keychain에 접근할 수 없습니다. 잠금 상태를 확인해 주세요." }
}
