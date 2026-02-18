import Foundation
import CryptoKit
import CommonCrypto

/// Provides AES-256-GCM encryption/decryption for backup files.
///
/// Uses PBKDF2 for key derivation from user password (600k iterations for brute-force resistance).
/// Format: salt(32) + nonce(12) + ciphertext + tag(16)
enum BackupCrypto {

    enum CryptoError: LocalizedError {
        case keyDerivationFailed
        case encryptionFailed
        case decryptionFailed
        case invalidData

        var errorDescription: String? {
            switch self {
            case .keyDerivationFailed: return "Failed to derive encryption key"
            case .encryptionFailed: return "Encryption failed"
            case .decryptionFailed: return "Decryption failed. Wrong password?"
            case .invalidData: return "Invalid backup file format"
            }
        }
    }

    private static let saltLength = 32
    private static let iterations: UInt32 = 600_000
    private static let keyLength = 32 // AES-256

    // MARK: - Encrypt

    static func encrypt(data: Data, password: String) throws -> Data {
        let salt = generateSalt()
        let key = try deriveKey(password: password, salt: salt)

        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw CryptoError.encryptionFailed
        }

        // Format: salt + combined(nonce + ciphertext + tag)
        var result = Data()
        result.append(salt)
        result.append(combined)
        return result
    }

    // MARK: - Decrypt

    static func decrypt(data: Data, password: String) throws -> Data {
        let nonceByteCount = 12
        let tagByteCount = 16
        let minimumLength = saltLength + nonceByteCount + tagByteCount
        guard data.count > minimumLength else {
            throw CryptoError.invalidData
        }

        let salt = data.prefix(saltLength)
        let sealedData = data.dropFirst(saltLength)

        let key = try deriveKey(password: password, salt: Data(salt))

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: sealedData)
            let decrypted = try AES.GCM.open(sealedBox, using: key)
            return decrypted
        } catch {
            throw CryptoError.decryptionFailed
        }
    }

    // MARK: - Key Derivation

    private static func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8) else {
            throw CryptoError.keyDerivationFailed
        }

        var derivedKey = Data(count: keyLength)
        let result = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }

        guard result == kCCSuccess else {
            throw CryptoError.keyDerivationFailed
        }

        return SymmetricKey(data: derivedKey)
    }

    // MARK: - Salt Generation

    private static func generateSalt() -> Data {
        var salt = Data(count: saltLength)
        _ = salt.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, saltLength, bytes.baseAddress!)
        }
        return salt
    }
}
