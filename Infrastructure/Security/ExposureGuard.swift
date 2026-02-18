import Foundation
import CoreSpotlight
import os.log

/// Actively prevents content exposure through iOS system features.
///
/// On every app launch this service:
/// 1. Deletes all Spotlight index entries (defensive purge)
/// 2. Validates no NSUserActivity indexing is configured
/// 3. Provides a privacy screen flag for App Switcher masking
///
/// Always-on, zero-configuration — appropriate for a privacy-first app.
@MainActor
final class ExposureGuard: ObservableObject, ExposureGuardServiceProtocol {

    // MARK: - Types

    /// Abstraction over CSSearchableIndex for testability.
    protocol SpotlightIndexing: AnyObject {
        func deleteAllSearchableItems(completionHandler: ((Error?) -> Void)?)
    }

    // MARK: - Published State

    @Published private(set) var isPrivacyScreenVisible: Bool = false

    // MARK: - Private

    private let spotlightIndex: SpotlightIndexing
    private let logger = Logger(subsystem: "com.lifememo.app", category: "ExposureGuard")

    // MARK: - Init

    init() {
        self.spotlightIndex = CSSearchableIndexWrapper()
        deleteSpotlightIndex()
    }

    init(spotlightIndex: SpotlightIndexing) {
        self.spotlightIndex = spotlightIndex
        deleteSpotlightIndex()
    }

    // MARK: - ExposureGuardServiceProtocol

    func enforceOnLaunch() {
        deleteSpotlightIndex()
        auditExposureVectors()
        logger.info("ExposureGuard: all exposure vectors neutralized on launch")
    }

    func handleScenePhase(_ phase: ScenePhaseValue) {
        switch phase {
        case .active:
            isPrivacyScreenVisible = false
        case .inactive, .background:
            isPrivacyScreenVisible = true
        }
    }

    func auditExposureVectors() {
        var violations: [String] = []

        if let activityTypes = Bundle.main.object(
            forInfoDictionaryKey: "NSUserActivityTypes"
        ) as? [String], !activityTypes.isEmpty {
            violations.append("Info.plist declares NSUserActivityTypes: \(activityTypes)")
        }

        if let extensionInfo = Bundle.main.object(
            forInfoDictionaryKey: "NSExtension"
        ) as? [String: Any] {
            violations.append("NSExtension found in Info.plist: \(extensionInfo.keys.joined(separator: ", "))")
        }

        if violations.isEmpty {
            logger.debug("ExposureGuard audit: PASS — no exposure vectors detected")
        } else {
            for violation in violations {
                logger.error("ExposureGuard audit VIOLATION: \(violation)")
            }
            #if DEBUG
            assertionFailure("ExposureGuard: \(violations.count) exposure violation(s) detected")
            #endif
        }
    }

    // MARK: - NSUserActivity Validation

    /// Checks that no window scenes have user activities set.
    /// Returns identifiers of scenes with violations.
    func validateNoUserActivity(in scenes: [WindowSceneActivityInfo]) -> [String] {
        scenes
            .filter(\.hasUserActivity)
            .map(\.sceneIdentifier)
    }

    // MARK: - Spotlight

    private func deleteSpotlightIndex() {
        spotlightIndex.deleteAllSearchableItems { [logger] error in
            if let error {
                logger.error("ExposureGuard: Spotlight deletion failed: \(error.localizedDescription)")
            } else {
                logger.debug("ExposureGuard: Spotlight index purged")
            }
        }
    }
}

// MARK: - WindowSceneActivityInfo

/// Value-type snapshot of a UIWindowScene for testable user-activity validation.
struct WindowSceneActivityInfo {
    let sceneIdentifier: String
    let hasUserActivity: Bool
}

// MARK: - CSSearchableIndex Wrapper

/// Wraps CSSearchableIndex so production code uses the real index while tests inject a spy.
private final class CSSearchableIndexWrapper: ExposureGuard.SpotlightIndexing {

    func deleteAllSearchableItems(completionHandler: ((Error?) -> Void)?) {
        guard CSSearchableIndex.isIndexingAvailable() else {
            completionHandler?(nil)
            return
        }
        CSSearchableIndex.default().deleteAllSearchableItems(completionHandler: completionHandler)
    }
}
