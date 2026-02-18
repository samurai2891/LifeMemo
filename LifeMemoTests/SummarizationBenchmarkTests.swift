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

    func testRunSingleSmall() async {
        let benchmark = SummarizationBenchmark()
        let result = await benchmark.runSingle(size: .small)
        XCTAssertGreaterThan(result.wordCount, 0)
        XCTAssertGreaterThan(result.processingTimeMs, 0)
        XCTAssertGreaterThan(result.sentenceCount, 0)
        XCTAssertFalse(result.thermalState.isEmpty)
    }

    func testWordsPerSecond() {
        let result = SummarizationBenchmark.BenchmarkResult(
            id: UUID(),
            inputSize: .small,
            wordCount: 1000,
            processingTimeMs: 500,
            peakMemoryMB: 10,
            thermalState: "Normal",
            sentenceCount: 5,
            keywordCount: 10,
            timestamp: Date()
        )
        XCTAssertEqual(result.wordsPerSecond, 2000, accuracy: 0.1) // 1000 words / 0.5 sec
    }

    func testWordsPerSecondZeroDuration() {
        let result = SummarizationBenchmark.BenchmarkResult(
            id: UUID(),
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
}
