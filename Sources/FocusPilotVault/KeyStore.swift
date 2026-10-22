import Foundation
import Security

public struct RecoveryKeyFile: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var vaultID: UUID
    public var key: String

    public init(schemaVersion: Int = 1, vaultID: UUID, keyData: Data) {
        self.schemaVersion = schemaVersion
        self.vaultID = vaultID
        self.key = keyData.base64EncodedString()
    }

    public var keyData: Data? { Data(base64Encoded: key) }
}

public enum KeyStoreError: LocalizedError {
    case keychain(OSStatus)
    case invalidRecoveryFile

    public var errorDescription: String? {
        switch self {
        case .keychain(let status): "Keychain operation failed with status \(status)."
        case .invalidRecoveryFile: "The recovery-key file is invalid."
        }
    }
}

public enum VaultKeyStore {
    private static let service = "com.focuspilot.vault"

    public static func save(_ key: Data, vaultID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultID.uuidString
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = key
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyStoreError.keychain(status) }
    }

    public static func load(vaultID: UUID) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeyStoreError.keychain(status)
        }
        return data
    }

    public static func exportFile(vaultID: UUID, key: Data, to url: URL) throws {
        try JSONEncoder.vaultEncoder.encode(RecoveryKeyFile(vaultID: vaultID, keyData: key))
            .write(to: url, options: .atomic)
    }

    public static func importFile(from url: URL) throws -> RecoveryKeyFile {
        let file = try JSONDecoder.vaultDecoder.decode(RecoveryKeyFile.self, from: Data(contentsOf: url))
        guard file.keyData?.count == 32 else { throw KeyStoreError.invalidRecoveryFile }
        return file
    }
}
