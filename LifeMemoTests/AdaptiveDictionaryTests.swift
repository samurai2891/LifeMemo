import Foundation
import Testing
@testable import LifeMemo

struct AdaptiveDictionaryTests {
    /// Create a fresh dictionary backed by an ephemeral UserDefaults suite.
    private func makeSUT() -> AdaptiveDictionary {
        let suite = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return AdaptiveDictionary(
            storage: suite,
            storageKey: "test.adaptive",
            maxEntries: 10
        )
    }

    // MARK: - Empty dictionary

    @Test func emptyDictionaryDoesNotModifyText() {
        let sut = makeSUT()
        let input = "会技を確認する"
        #expect(sut.apply(input) == input)
    }

    @Test func emptyDictionaryHasZeroEntries() {
        let sut = makeSUT()
        #expect(sut.entryCount == 0)
    }

    // MARK: - Learning and applying

    @Test func learnedCorrectionApplied() {
        let sut = makeSUT()
        sut.learn(original: "会技", replacement: "会議", precedingWord: nil)
        #expect(sut.apply("今日の会技") == "今日の会議")
    }

    @Test func contextAwareCorrectionApplied() {
        let sut = makeSUT()
        sut.learn(original: "会技", replacement: "会議", precedingWord: "定例")
        // Should correct when preceded by 定例
        #expect(sut.apply("定例会技") == "定例会議")
        // Should NOT correct without the context word (no non-contextual rule)
        #expect(sut.apply("緊急会技") == "緊急会技")
    }

    @Test func multipleCorrectionsBothApplied() {
        let sut = makeSUT()
        sut.learn(original: "会技", replacement: "会議", precedingWord: nil)
        sut.learn(original: "核人", replacement: "確認", precedingWord: nil)
        let result = sut.apply("会技と核人")
        #expect(result == "会議と確認")
    }

    // MARK: - Frequency tracking

    @Test func repeatedLearningIncreasesFrequency() {
        let sut = makeSUT()
        sut.learn(original: "会技", replacement: "会議", precedingWord: nil)
        sut.learn(original: "会技", replacement: "会議", precedingWord: nil)
        sut.learn(original: "会技", replacement: "会議", precedingWord: nil)
        // Still only one entry, just with higher frequency
        #expect(sut.entryCount == 1)
    }

    // MARK: - Max entries eviction

    @Test func entriesBeyondMaxEvicted() {
        let sut = makeSUT() // maxEntries = 10
        for i in 0..<15 {
            sut.learn(
                original: "word\(i)",
                replacement: "fixed\(i)",
                precedingWord: nil
            )
        }
        #expect(sut.entryCount <= 10)
    }

    // MARK: - Forget

    @Test func forgetRemovesSpecificEntry() {
        let sut = makeSUT()
        sut.learn(original: "会技", replacement: "会議", precedingWord: nil)
        sut.learn(original: "核人", replacement: "確認", precedingWord: nil)
        sut.forget(original: "会技", replacement: "会議", precedingWord: nil)
        #expect(sut.entryCount == 1)
        #expect(sut.apply("会技") == "会技") // No longer corrected
    }

    // MARK: - Clear all

    @Test func clearAllRemovesEverything() {
        let sut = makeSUT()
        sut.learn(original: "会技", replacement: "会議", precedingWord: nil)
        sut.learn(original: "核人", replacement: "確認", precedingWord: nil)
        sut.clearAll()
        #expect(sut.entryCount == 0)
    }

    // MARK: - Edge cases

    @Test func learningSameOriginalAndReplacementIgnored() {
        let sut = makeSUT()
        sut.learn(original: "会議", replacement: "会議", precedingWord: nil)
        #expect(sut.entryCount == 0)
    }

    @Test func learningEmptyOriginalIgnored() {
        let sut = makeSUT()
        sut.learn(original: "", replacement: "会議", precedingWord: nil)
        #expect(sut.entryCount == 0)
    }
}
