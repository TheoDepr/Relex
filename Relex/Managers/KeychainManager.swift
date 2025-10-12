//
//  KeychainManager.swift
//  Relex
//
//  Secure storage for sensitive credentials using macOS Keychain
//

import Foundation
import Security

@MainActor
class KeychainManager {
    static let shared = KeychainManager()

    // Service identifier for Keychain items
    private let service = "com.relex.apikeys"
    private let openAIKeyAccount = "openai-api-key"

    private init() {}

    // MARK: - Public API

    /// Store API key securely in Keychain
    func setAPIKey(_ key: String) throws {
        guard !key.isEmpty else {
            // If empty string, delete the key
            try deleteAPIKey()
            return
        }

        // Convert key to Data
        guard let keyData = key.data(using: .utf8) else {
            throw KeychainError.encodingError
        }

        // Check if key already exists
        let existingItem = try? getAPIKeyData()

        if existingItem != nil {
            // Update existing item
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: openAIKeyAccount
            ]

            let attributes: [String: Any] = [
                kSecValueData as String: keyData,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]

            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

            guard status == errSecSuccess else {
                throw KeychainError.updateFailed(status: status)
            }
        } else {
            // Add new item
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: openAIKeyAccount,
                kSecValueData as String: keyData,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                kSecAttrSynchronizable as String: false // Don't sync via iCloud for security
            ]

            let status = SecItemAdd(query as CFDictionary, nil)

            guard status == errSecSuccess else {
                throw KeychainError.saveFailed(status: status)
            }
        }

        print("🔐 API key securely stored in Keychain")
    }

    /// Retrieve API key from Keychain
    func getAPIKey() -> String {
        do {
            let data = try getAPIKeyData()
            guard let key = String(data: data, encoding: .utf8) else {
                print("⚠️ Failed to decode API key from Keychain")
                return ""
            }
            return key
        } catch {
            // Key doesn't exist or error occurred
            return ""
        }
    }

    /// Check if API key exists in Keychain
    func hasAPIKey() -> Bool {
        return !getAPIKey().isEmpty
    }

    /// Delete API key from Keychain
    func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: openAIKeyAccount
        ]

        let status = SecItemDelete(query as CFDictionary)

        // Success if deleted or if item didn't exist
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }

        print("🔐 API key deleted from Keychain")
    }

    // MARK: - Migration Support

    /// Migrate API key from UserDefaults to Keychain
    func migrateFromUserDefaults() {
        // First check if key already exists in Keychain - if so, skip migration
        if hasAPIKey() {
            // Clean up UserDefaults if it still has the old key
            if UserDefaults.standard.string(forKey: "OpenAIAPIKey") != nil {
                UserDefaults.standard.removeObject(forKey: "OpenAIAPIKey")
                UserDefaults.standard.synchronize()
                print("🧹 Cleaned up old API key from UserDefaults")
            }
            return
        }

        // Check if there's a key in UserDefaults to migrate
        guard let oldKey = UserDefaults.standard.string(forKey: "OpenAIAPIKey"),
              !oldKey.isEmpty else {
            return
        }

        print("🔄 Migrating API key from UserDefaults to Keychain...")

        do {
            // Save to Keychain
            try setAPIKey(oldKey)

            // Remove from UserDefaults
            UserDefaults.standard.removeObject(forKey: "OpenAIAPIKey")
            UserDefaults.standard.synchronize()

            print("✅ API key successfully migrated to Keychain")
        } catch {
            print("❌ Failed to migrate API key: \(error.localizedDescription)")
            // Don't remove from UserDefaults if migration failed
        }
    }

    // MARK: - Private Helpers

    private func getAPIKeyData() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: openAIKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            throw KeychainError.notFound
        }

        guard let data = result as? Data else {
            throw KeychainError.unexpectedData
        }

        return data
    }
}

// MARK: - Keychain Errors

enum KeychainError: LocalizedError {
    case encodingError
    case saveFailed(status: OSStatus)
    case updateFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case notFound
    case unexpectedData

    var errorDescription: String? {
        switch self {
        case .encodingError:
            return "Failed to encode API key"
        case .saveFailed(let status):
            return "Failed to save to Keychain (status: \(status))"
        case .updateFailed(let status):
            return "Failed to update Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain (status: \(status))"
        case .notFound:
            return "API key not found in Keychain"
        case .unexpectedData:
            return "Unexpected data format in Keychain"
        }
    }
}
