import XCTest
import Combine
@testable import LifeMemo

// MARK: - Spotlight Index Spy

final class SpotlightIndexSpy: ExposureGuard.SpotlightIndexing {

    private(set) var deleteAllCallCount = 0
    var deleteError: Error?

    func deleteAllSearchableItems(completionHandler: ((Error?) -> Void)?) {
        deleteAllCallCount += 1
        completionHandler?(deleteError)
    }
}

// MARK: - ExposureGuardTests

@MainActor
final class ExposureGuardTests: XCTestCase {

    private var sut: ExposureGuard!
    private var spotlightSpy: SpotlightIndexSpy!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        spotlightSpy = SpotlightIndexSpy()
        sut = ExposureGuard(spotlightIndex: spotlightSpy)
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        spotlightSpy = nil
        super.tearDown()
    }

    // MARK: - Instantiation

    func testInstantiationSucceeds() {
        XCTAssertNotNil(sut, "ExposureGuard must be creatable without errors")
    }

    func testInstantiationWithRealSpotlightDoesNotCrash() {
        let guard_ = ExposureGuard()
        XCTAssertNotNil(guard_)
    }

    // MARK: - Spotlight Deletion

    func testSpotlightDeleteCalledOnInit() {
        XCTAssertEqual(
            spotlightSpy.deleteAllCallCount, 1,
            "deleteAllSearchableItems must be called exactly once during init"
        )
    }

    func testSpotlightDeleteCalledOnlyOncePerInit() {
        let secondSpy = SpotlightIndexSpy()
        _ = ExposureGuard(spotlightIndex: secondSpy)
        XCTAssertEqual(secondSpy.deleteAllCallCount, 1)
    }

    func testSpotlightDeleteNotRepeatedOnPhaseChange() {
        sut.handleScenePhase(.active)
        sut.handleScenePhase(.inactive)
        sut.handleScenePhase(.background)
        XCTAssertEqual(
            spotlightSpy.deleteAllCallCount, 1,
            "Spotlight deletion must happen only in init, not on phase changes"
        )
    }

    func testSpotlightDeleteHandlesErrorGracefully() {
        struct FakeError: Error {}
        let spyWithError = SpotlightIndexSpy()
        spyWithError.deleteError = FakeError()
        let guard_ = ExposureGuard(spotlightIndex: spyWithError)
        XCTAssertNotNil(guard_, "ExposureGuard must survive a Spotlight deletion error")
        XCTAssertEqual(spyWithError.deleteAllCallCount, 1)
    }

    // MARK: - Initial State

    func testPrivacyScreenHiddenOnInit() {
        XCTAssertFalse(
            sut.isPrivacyScreenVisible,
            "Privacy screen must not be visible immediately after init"
        )
    }

    // MARK: - Scene Phase Transitions

    func testPrivacyScreenShowsOnInactive() {
        sut.handleScenePhase(.inactive)
        XCTAssertTrue(sut.isPrivacyScreenVisible,
                      "Privacy screen must appear on inactive")
    }

    func testPrivacyScreenShowsOnBackground() {
        sut.handleScenePhase(.background)
        XCTAssertTrue(sut.isPrivacyScreenVisible,
                      "Privacy screen must appear on background")
    }

    func testPrivacyScreenHidesOnActive() {
        sut.handleScenePhase(.inactive)
        sut.handleScenePhase(.active)
        XCTAssertFalse(sut.isPrivacyScreenVisible,
                       "Privacy screen must hide when returning to active")
    }

    func testPrivacyScreenHidesFromBackgroundToActive() {
        sut.handleScenePhase(.background)
        sut.handleScenePhase(.active)
        XCTAssertFalse(sut.isPrivacyScreenVisible,
                       "Privacy screen must hide after returning from background")
    }

    func testInactiveToBackgroundKeepsPrivacyScreen() {
        sut.handleScenePhase(.inactive)
        sut.handleScenePhase(.background)
        XCTAssertTrue(sut.isPrivacyScreenVisible,
                      "Privacy screen must stay visible during inactive to background")
    }

    func testRepeatedActiveDoesNotShowPrivacyScreen() {
        sut.handleScenePhase(.active)
        sut.handleScenePhase(.active)
        XCTAssertFalse(sut.isPrivacyScreenVisible,
                       "Privacy screen must remain hidden on repeated active")
    }

    func testFullLifecycleSequence() {
        sut.handleScenePhase(.active)
        XCTAssertFalse(sut.isPrivacyScreenVisible, "Step 1: active — hidden")

        sut.handleScenePhase(.inactive)
        XCTAssertTrue(sut.isPrivacyScreenVisible, "Step 2: inactive — visible")

        sut.handleScenePhase(.background)
        XCTAssertTrue(sut.isPrivacyScreenVisible, "Step 3: background — visible")

        sut.handleScenePhase(.active)
        XCTAssertFalse(sut.isPrivacyScreenVisible, "Step 4: active — hidden")
    }

    // MARK: - Combine Publisher

    func testPublisherEmitsTrueOnInactive() {
        var received: [Bool] = []
        let exp = expectation(description: "Publisher emits true")

        sut.$isPrivacyScreenVisible
            .dropFirst()
            .sink { received.append($0); exp.fulfill() }
            .store(in: &cancellables)

        sut.handleScenePhase(.inactive)
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(received, [true])
    }

    func testPublisherEmitsFalseOnReturnToActive() {
        var received: [Bool] = []
        let exp = expectation(description: "Publisher emits false")
        exp.expectedFulfillmentCount = 2

        sut.$isPrivacyScreenVisible
            .dropFirst()
            .sink { received.append($0); exp.fulfill() }
            .store(in: &cancellables)

        sut.handleScenePhase(.inactive)
        sut.handleScenePhase(.active)
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(received, [true, false])
    }

    // MARK: - NSUserActivity Validation

    func testNoViolationsWithEmptyScenes() {
        let violations = sut.validateNoUserActivity(in: [])
        XCTAssertTrue(violations.isEmpty,
                      "No violations when there are no window scenes")
    }

    func testViolationDetectedForSceneWithActivity() {
        let info = WindowSceneActivityInfo(sceneIdentifier: "main", hasUserActivity: true)
        let violations = sut.validateNoUserActivity(in: [info])
        XCTAssertEqual(violations, ["main"])
    }

    func testNoViolationForSceneWithoutActivity() {
        let info = WindowSceneActivityInfo(sceneIdentifier: "main", hasUserActivity: false)
        let violations = sut.validateNoUserActivity(in: [info])
        XCTAssertTrue(violations.isEmpty)
    }

    func testMixedScenesReportsOnlyViolations() {
        let clean = WindowSceneActivityInfo(sceneIdentifier: "clean", hasUserActivity: false)
        let dirty = WindowSceneActivityInfo(sceneIdentifier: "dirty", hasUserActivity: true)
        let violations = sut.validateNoUserActivity(in: [clean, dirty])
        XCTAssertEqual(violations, ["dirty"])
    }

    func testMultipleViolationsReported() {
        let infos = [
            WindowSceneActivityInfo(sceneIdentifier: "sceneA", hasUserActivity: true),
            WindowSceneActivityInfo(sceneIdentifier: "sceneB", hasUserActivity: false),
            WindowSceneActivityInfo(sceneIdentifier: "sceneC", hasUserActivity: true),
        ]
        let violations = sut.validateNoUserActivity(in: infos)
        XCTAssertEqual(violations.count, 2)
        XCTAssertTrue(violations.contains("sceneA"))
        XCTAssertTrue(violations.contains("sceneC"))
    }
}
