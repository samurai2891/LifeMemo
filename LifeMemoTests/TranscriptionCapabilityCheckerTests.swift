import XCTest
@testable import LifeMemo

@MainActor
final class TranscriptionCapabilityCheckerTests: XCTestCase {

    private var checker: TranscriptionCapabilityChecker!

    override func setUp() {
        super.setUp()
        checker = TranscriptionCapabilityChecker()
    }

    override func tearDown() {
        checker = nil
        super.tearDown()
    }

    // MARK: - Check with Locale

    func testCheckWithEnglishLocale() {
        let result = checker.check(for: Locale(identifier: "en-US"))
        // On simulator, speech recognition may not be fully available.
        // Verify the method returns one of the valid Capability cases.
        switch result {
        case .available:
            XCTAssertTrue(result.isAvailable)
        case .unavailableNoRecognizer, .unavailableNotReady, .unavailableNoOnDevice:
            XCTAssertFalse(result.isAvailable)
        }
    }

    func testCheckWithJapaneseLocale() {
        let result = checker.check(for: Locale(identifier: "ja-JP"))
        switch result {
        case .available:
            XCTAssertTrue(result.isAvailable)
        case .unavailableNoRecognizer, .unavailableNotReady, .unavailableNoOnDevice:
            XCTAssertFalse(result.isAvailable)
        }
    }

    // MARK: - Check with LanguageMode

    func testCheckWithAutoLanguageMode() {
        let result = checker.check(for: LanguageMode.auto)
        // Just verify no crash and a valid result is returned
        _ = result.isAvailable
        XCTAssertFalse(result.userMessage.isEmpty)
    }

    func testCheckWithEnglishLanguageMode() {
        let result = checker.check(for: LanguageMode.english)
        XCTAssertFalse(result.userMessage.isEmpty)
    }

    // MARK: - Exotic / Invalid Locale

    func testCheckWithUnsupportedLocale() {
        let result = checker.check(for: Locale(identifier: "xx-XX"))
        // An unsupported locale should return unavailableNoRecognizer
        XCTAssertEqual(result, .unavailableNoRecognizer)
        XCTAssertFalse(result.isAvailable)
    }

    // MARK: - Capability Properties

    func testCapabilityIsAvailable() {
        XCTAssertTrue(TranscriptionCapabilityChecker.Capability.available.isAvailable)
        XCTAssertFalse(TranscriptionCapabilityChecker.Capability.unavailableNoRecognizer.isAvailable)
        XCTAssertFalse(TranscriptionCapabilityChecker.Capability.unavailableNotReady.isAvailable)
        XCTAssertFalse(TranscriptionCapabilityChecker.Capability.unavailableNoOnDevice.isAvailable)
    }

    func testCapabilityUserMessages() {
        let cases: [TranscriptionCapabilityChecker.Capability] = [
            .available, .unavailableNoRecognizer, .unavailableNotReady, .unavailableNoOnDevice
        ]
        for capability in cases {
            XCTAssertFalse(capability.userMessage.isEmpty,
                           "\(capability) should have a non-empty user message")
        }
    }

    func testCapabilityEquatable() {
        XCTAssertEqual(
            TranscriptionCapabilityChecker.Capability.available,
            TranscriptionCapabilityChecker.Capability.available
        )
        XCTAssertNotEqual(
            TranscriptionCapabilityChecker.Capability.available,
            TranscriptionCapabilityChecker.Capability.unavailableNoRecognizer
        )
    }
}
