import Foundation
import os.log

/// Benchmarks on-device summarization performance across different text sizes and algorithms.
/// Measures latency, memory usage, and thermal state.
@MainActor
final class SummarizationBenchmark: ObservableObject {

    // MARK: - Types

    struct BenchmarkResult: Identifiable, Equatable {
        let id: UUID
        let algorithm: SummarizationAlgorithm
        let inputSize: InputSize
        let wordCount: Int
        let processingTimeMs: Double
        let peakMemoryMB: Double
        let thermalState: String
        let sentenceCount: Int
        let keywordCount: Int
        let timestamp: Date

        var wordsPerSecond: Double {
            guard processingTimeMs > 0 else { return 0 }
            return Double(wordCount) / (processingTimeMs / 1000.0)
        }
    }

    enum InputSize: String, CaseIterable, Identifiable {
        case small = "Small (~100 words)"
        case medium = "Medium (~500 words)"
        case large = "Large (~2000 words)"
        case extraLarge = "XL (~5000 words)"

        var id: String { rawValue }

        var approximateWordCount: Int {
            switch self {
            case .small: return 100
            case .medium: return 500
            case .large: return 2000
            case .extraLarge: return 5000
            }
        }
    }

    // MARK: - Published State

    @Published private(set) var results: [BenchmarkResult] = []
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var currentTest: String = ""

    // MARK: - Dependencies

    private let logger = Logger(subsystem: "com.lifememo.app", category: "Benchmark")

    // MARK: - Public API

    /// Runs benchmarks for all input sizes and algorithms sequentially.
    func runAll() async {
        isRunning = true
        results = []

        for algorithm in SummarizationAlgorithm.allCases {
            for size in InputSize.allCases {
                currentTest = "Testing \(algorithm.displayName) \(size.rawValue)..."
                let result = await runSingle(size: size, algorithm: algorithm)
                results.append(result)
                logger.info(
                    "Benchmark \(algorithm.displayName) \(size.rawValue): \(result.processingTimeMs, format: .fixed(precision: 1))ms, \(result.wordsPerSecond, format: .fixed(precision: 0)) words/sec"
                )
            }
        }

        currentTest = ""
        isRunning = false
    }

    /// Run benchmark for a single algorithm and input size.
    func runSingle(size: InputSize, algorithm: SummarizationAlgorithm = .tfidf) async -> BenchmarkResult {
        let text = generateTestText(wordCount: size.approximateWordCount)
        let memBefore = currentMemoryMB()
        let thermal = thermalStateString()

        let start = CFAbsoluteTimeGetCurrent()
        let summaryResult: SummarizationResult

        switch algorithm {
        case .tfidf:
            let summarizer = NLExtractiveSummarizer()
            summaryResult = summarizer.summarize(text: text)
        case .textRank:
            let summarizer = TextRankSummarizer()
            summaryResult = summarizer.summarize(text: text)
        case .leadBased:
            let summarizer = LeadSummarizer()
            summaryResult = summarizer.summarize(text: text)
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        let memAfter = currentMemoryMB()

        return BenchmarkResult(
            id: UUID(),
            algorithm: algorithm,
            inputSize: size,
            wordCount: summaryResult.inputWordCount,
            processingTimeMs: elapsed,
            peakMemoryMB: max(0, memAfter - memBefore),
            thermalState: thermal,
            sentenceCount: summaryResult.sentences.count,
            keywordCount: summaryResult.keywords.count,
            timestamp: Date()
        )
    }

    // MARK: - Private Helpers

    private static let baseParagraphs: [String] = [
        "Today we discussed the quarterly results for the company. Revenue increased by fifteen percent compared to last quarter. The marketing team presented their new campaign strategy focusing on digital channels. Customer satisfaction scores improved significantly across all regions. We need to finalize the budget proposal before next Friday.",
        "The engineering team demonstrated the new search feature during the sprint review. Performance benchmarks showed a forty percent improvement in query response time. Several edge cases were identified during testing that require additional validation. The team agreed to prioritize accessibility improvements in the next iteration.",
        "Product management shared the updated roadmap for the second half of the year. Three major initiatives were approved including the mobile redesign and analytics dashboard. Stakeholder feedback highlighted the importance of data export capabilities. The timeline was adjusted to accommodate additional user research sessions."
    ]

    private func generateTestText(wordCount: Int) -> String {
        let allParagraphs = Self.baseParagraphs
        var accumulated: [String] = []
        var currentWordCount = 0
        var index = 0

        while currentWordCount < wordCount {
            let paragraph = allParagraphs[index % allParagraphs.count]
            accumulated.append(paragraph)
            currentWordCount += paragraph.split(separator: " ").count
            index += 1
        }

        let joined = accumulated.joined(separator: " ")
        let words = joined.split(separator: " ")
        return words.prefix(wordCount).joined(separator: " ")
    }

    private func currentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / (1024.0 * 1024.0)
    }

    private func thermalStateString() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return "Normal"
        case .fair:     return "Fair"
        case .serious:  return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}
