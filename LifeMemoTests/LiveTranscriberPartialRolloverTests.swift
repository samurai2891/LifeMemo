import XCTest
@testable import LifeMemo

final class LiveTranscriberPartialRolloverTests: XCTestCase {

    func testGrowingPartialDoesNotCommitPrevious() {
        let shouldCommit = LiveTranscriber.shouldCommitPreviousPartial(
            previousPartial: "hello",
            newPartial: "hello world"
        )
        XCTAssertFalse(shouldCommit)
    }

    func testSamePartialDoesNotCommitPrevious() {
        let shouldCommit = LiveTranscriber.shouldCommitPreviousPartial(
            previousPartial: "こんにちは",
            newPartial: "こんにちは"
        )
        XCTAssertFalse(shouldCommit)
    }

    func testResetToDifferentUtteranceCommitsPrevious() {
        let shouldCommit = LiveTranscriber.shouldCommitPreviousPartial(
            previousPartial: "今日は会議の予定を確認します",
            newPartial: "次に議題に入ります"
        )
        XCTAssertTrue(shouldCommit)
    }

    func testLargeShrinkWithWeakPrefixCommitsPrevious() {
        let shouldCommit = LiveTranscriber.shouldCommitPreviousPartial(
            previousPartial: "プロジェクトの進捗を共有します",
            newPartial: "プロジェクト"
        )
        XCTAssertTrue(shouldCommit)
    }

    func testWhitespaceOnlyChangeDoesNotCommitPrevious() {
        let shouldCommit = LiveTranscriber.shouldCommitPreviousPartial(
            previousPartial: "hello   world",
            newPartial: "hello world"
        )
        XCTAssertFalse(shouldCommit)
    }

    func testShrinkAfterSilenceCommitsPrevious() {
        let shouldCommit = LiveTranscriber.shouldCommitPreviousPartial(
            previousPartial: "今日は会議の予定を確認します",
            newPartial: "今日は会議の予定",
            silenceGapSec: 1.5
        )
        XCTAssertTrue(shouldCommit)
    }

    func testSmallShrinkWithoutSilenceDoesNotCommitImmediately() {
        let shouldCommit = LiveTranscriber.shouldCommitPreviousPartial(
            previousPartial: "今日は会議の予定を確認します",
            newPartial: "今日は会議の予定",
            silenceGapSec: 0.2
        )
        XCTAssertFalse(shouldCommit)
    }
}
