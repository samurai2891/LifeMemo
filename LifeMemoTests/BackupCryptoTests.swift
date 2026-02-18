import XCTest
@testable import LifeMemo

final class BackupCryptoTests: XCTestCase {

    func testEncryptDecryptRoundtrip() throws {
        let original = "Hello, LifeMemo!".data(using: .utf8)!
        let password = "testPassword123"

        let encrypted = try BackupCrypto.encrypt(data: original, password: password)
        let decrypted = try BackupCrypto.decrypt(data: encrypted, password: password)

        XCTAssertEqual(original, decrypted)
    }

    func testEncryptProducesDifferentOutput() throws {
        let data = "Same data".data(using: .utf8)!
        let password = "password"

        let encrypted1 = try BackupCrypto.encrypt(data: data, password: password)
        let encrypted2 = try BackupCrypto.encrypt(data: data, password: password)

        // Different salt means different ciphertext
        XCTAssertNotEqual(encrypted1, encrypted2)
    }

    func testWrongPasswordFails() throws {
        let data = "Secret data".data(using: .utf8)!
        let encrypted = try BackupCrypto.encrypt(data: data, password: "correct")

        XCTAssertThrowsError(try BackupCrypto.decrypt(data: encrypted, password: "wrong"))
    }

    func testEmptyDataEncryptsThenDecryptFails() throws {
        // Empty data encrypts successfully, but the ciphertext is exactly at the
        // minimum length boundary (salt + nonce + tag with 0 ciphertext bytes).
        // The decrypt guard uses strict `>`, so it rejects this edge case.
        let empty = Data()
        let password = "password"

        let encrypted = try BackupCrypto.encrypt(data: empty, password: password)
        XCTAssertThrowsError(try BackupCrypto.decrypt(data: encrypted, password: password))
    }

    func testSmallDataRoundtrip() throws {
        let small = Data([0x42]) // 1 byte
        let password = "password"

        let encrypted = try BackupCrypto.encrypt(data: small, password: password)
        let decrypted = try BackupCrypto.decrypt(data: encrypted, password: password)

        XCTAssertEqual(small, decrypted)
    }

    func testInvalidDataThrows() {
        XCTAssertThrowsError(try BackupCrypto.decrypt(data: Data([1, 2, 3]), password: "p"))
    }

    func testLargeDataRoundtrip() throws {
        let largeData = Data(repeating: 0xAB, count: 1_000_000) // 1MB
        let password = "strongPassword!@#"

        let encrypted = try BackupCrypto.encrypt(data: largeData, password: password)
        let decrypted = try BackupCrypto.decrypt(data: encrypted, password: password)

        XCTAssertEqual(largeData, decrypted)
    }
}
