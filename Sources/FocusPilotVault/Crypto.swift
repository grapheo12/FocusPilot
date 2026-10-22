import CryptoKit
import Foundation

public struct EncryptedEnvelope: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var algorithm: String
    public var nonce: String
    public var ciphertext: String
    public var tag: String

    public init(schemaVersion: Int = 1, nonce: Data, ciphertext: Data, tag: Data) {
        self.schemaVersion = schemaVersion
        self.algorithm = "AES-256-GCM"
        self.nonce = nonce.base64EncodedString()
        self.ciphertext = ciphertext.base64EncodedString()
        self.tag = tag.base64EncodedString()
    }
}

public enum VaultCryptoError: LocalizedError {
    case invalidKey
    case invalidEnvelope
    case unsupportedAlgorithm

    public var errorDescription: String? {
        switch self {
        case .invalidKey: "The vault key is not 256 bits."
        case .invalidEnvelope: "The encrypted vault file is malformed."
        case .unsupportedAlgorithm: "The vault uses an unsupported encryption algorithm."
        }
    }
}

public enum VaultCrypto {
    public static func generateKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    public static func encrypt<T: Encodable>(_ value: T, key: Data) throws -> EncryptedEnvelope {
        guard key.count == 32 else { throw VaultCryptoError.invalidKey }
        let encoder = JSONEncoder.vaultEncoder
        let plaintext = try encoder.encode(value)
        let sealed = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key))
        return EncryptedEnvelope(
            nonce: sealed.nonce.withUnsafeBytes { Data($0) },
            ciphertext: sealed.ciphertext,
            tag: sealed.tag
        )
    }

    public static func decrypt<T: Decodable>(
        _ type: T.Type,
        envelope: EncryptedEnvelope,
        key: Data
    ) throws -> T {
        guard key.count == 32 else { throw VaultCryptoError.invalidKey }
        guard envelope.algorithm == "AES-256-GCM" else { throw VaultCryptoError.unsupportedAlgorithm }
        guard let nonceData = Data(base64Encoded: envelope.nonce),
              let ciphertext = Data(base64Encoded: envelope.ciphertext),
              let tag = Data(base64Encoded: envelope.tag) else {
            throw VaultCryptoError.invalidEnvelope
        }
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let plaintext = try AES.GCM.open(box, using: SymmetricKey(data: key))
        return try JSONDecoder.vaultDecoder.decode(type, from: plaintext)
    }
}

public extension JSONEncoder {
    static var vaultEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

public extension JSONDecoder {
    static var vaultDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
