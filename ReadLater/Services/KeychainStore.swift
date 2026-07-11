import Foundation
import Security

/// Minimal Keychain helper for storing the OpenAI API key. Never persists the
/// raw key in UserDefaults or SwiftData.
enum KeychainStore {
    private static let service = "com.ellenbartling.readlater"

    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var attrs = base
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("KeychainStore.set failed for account %@: OSStatus %d", account, Int(status))
        }
        return status == errSecSuccess
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                NSLog("KeychainStore.get failed for account %@: OSStatus %d", account, Int(status))
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum Account {
        static let openAI = "openai.apiKey"
    }
}
