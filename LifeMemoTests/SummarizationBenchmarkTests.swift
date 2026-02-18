import XCTest
@testable import LifeMemo

@MainActor
final class SummarizationBenchmarkTests: XCTestCase {

    func testInitialState() {
        let benchmark = SummarizationBenchmark()
        XCTAssertTrue(benchmark.results.isEmpty)
        XCTAssertFalse(benchmark.isRunning)
        XCTAssertTrue(benchmark.currentTest.isEmpty)
    }

    func testInputSizeWordCounts() {
        XCTAssertEqual(SummarizationBenchmark.InputSize.small.approximateWordCount, 100)
        XCTAssertEqual(SummarizationBenchmark.InputSize.medium.approximateWordCount, 500)
        XCTAssertEqual(SummarizationBenchmark.InputSize.large.approximateWordCount, 2000)
        XCTAssertEqual(SummarizationBenchmark.InputSize.extraLarge.approximateWordCount, 5000)
    }

    func testAllInputSizes() {
        XCTAssertEqual(SummarizationBenchmark.InputSize.allCases.count, 4)
    }

    func testRunSingleSmallTFIDF() async {
        let benchmark = SummarizationBenchmark()
        let result = await benchmark.runSingle(size: .small, algorithm: .tfidf)
        XCTAssertGreaterThan(result.wordCount, 0)
        XCTAssertGreaterThan(result.processingTimeMs, 0)
        XCTAssertGreaterThan(result.sentenceCount, 0)
        XCTAssertFalse(result.thermalState.isEmpty)
        XCTAssertEqual(result.algorithm, .tfidf)
    }

    func testRunSingleSmallTextRank() async {
        let benchmark = SummarizationBenchmark()
        let result = await benchmark.runSingle(size: .small, algorithm: .textRank)
        XCTAssertGreaterThan(result.wordCount, 0)
        XCTAssertEqual(result.algorithm, .textRank)
    }

    func testRunSingleSmallLeadBased() async {
        let benchmark = SummarizationBenchmark()
        let result = await benchmark.runSingle(size: .small, algorithm: .leadBased)
        XCTAssertGreaterThan(result.wordCount, 0)
        XCTAssertEqual(result.algorithm, .leadBased)
    }

    func testWordsPerSecond() {
        let result = SummarizationBenchmark.BenchmarkResult(
            id: UUID(),
            algorithm: .tfidf,
            inputSize: .small,
            wordCount: 1000,
            processingTimeMs: 500,
            peakMemoryMB: 10,
            thermalState: "Normal",
            sentenceCount: 5,
            keywordCount: 10,
            timestamp: Date()
        )
        XCTAssertEqual(result.wordsPerSecond, 2000, accuracy: 0.1)
    }

    func testWordsPerSecondZeroDuration() {
        let result = SummarizationBenchmark.BenchmarkResult(
            id: UUID(),
            algorithm: .tfidf,
            inputSize: .small,
            wordCount: 100,
            processingTimeMs: 0,
            peakMemoryMB: 0,
            thermalState: "Normal",
            sentenceCount: 0,
            keywordCount: 0,
            timestamp: Date()
        )
        XCTAssertEqual(result.wordsPerSecond, 0)
    }

    func testDefaultAlgorithmIsTFIDF() async {
        let benchmark = SummarizationBenchmark()
        let result = await benchmark.runSingle(size: .small)
        XCTAssertEqual(result.algorithm, .tfidf)
    }
}
