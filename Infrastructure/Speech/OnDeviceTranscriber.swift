import Foundation
import Speech
import os.log

/// Detailed transcription result containing both formatted text and word-level data.
struct TranscriptionDetail {
    let formattedString: String
    let wordSegments: [WordSegmentInfo]
    let diagnostics: TranscriptionDiagnostics
    let selectedTextSource: TranscriptionTextSource
    let qualitySignals: TranscriptionQualitySignals

    init(
        formattedString: String,
        wordSegments: [WordSegmentInfo],
        diagnostics: TranscriptionDiagnostics? = nil,
        selectedTextSource: TranscriptionTextSource = .primaryFinal,
        qualitySignals: TranscriptionQualitySignals? = nil
    ) {
        self.formattedString = formattedString
        self.wordSegments = wordSegments
        self.selectedTextSource = selectedTextSource
        self.qualitySignals = qualitySignals ?? TranscriptionQualitySignals(
            primaryCoverage: 1.0,
            alignmentScore: 1.0,
            conflictWordRate: 0.0,
            primaryWordCount: wordSegments.count,
            consensusWordCount: wordSegments.count
        )
        self.diagnostics = diagnostics ?? TranscriptionDiagnostics(
            textLength: formattedString.count,
            wordCount: wordSegments.count,
            firstWordStartMs: wordSegments.first.map { Int64($0.timestamp * 1000) },
            lastWordEndMs: wordSegments.last.map { Int64(($0.timestamp + $0.duration) * 1000) },
            recognitionDurationMs: 0,
            textSource: selectedTextSource,
            fallbackReason: nil,
            conflictWordRate: self.qualitySignals.conflictWordRate,
            alignmentScore: self.qualitySignals.alignmentScore
        )
    }
}

enum TranscriptionTextSource: String {
    case primaryFinal
    case consensusFallback
}

struct TranscriptionQualitySignals {
    let primaryCoverage: Double
    let alignmentScore: Double
    let conflictWordRate: Double
    let primaryWordCount: Int
    let consensusWordCount: Int
}

/// Diagnostics captured from one URL-based recognition request.
struct TranscriptionDiagnostics {
    let textLength: Int
    let wordCount: Int
    let firstWordStartMs: Int64?
    let lastWordEndMs: Int64?
    let recognitionDurationMs: Int64
    let textSource: TranscriptionTextSource
    let fallbackReason: String?
    let conflictWordRate: Double
    let alignmentScore: Double
}

/// On-device speech transcription using Apple's Speech framework.
///
/// Uses `SFSpeechURLRecognitionRequest` with `requiresOnDeviceRecognition = true`
/// so that audio data never leaves the device. This satisfies privacy requirements
/// but limits support to languages that have on-device models downloaded.
final class OnDeviceTranscriber: TranscriptionServiceProtocol {

    private let logger = Logger(subsystem: "com.lifememo.app", category: "OnDeviceTranscriber")
    private let activeTaskLock = NSLock()
    private var activeRecognitionTask: SFSpeechRecognitionTask?

    /// Transcribes an audio file at the given URL using on-device recognition.
    ///
    /// - Parameters:
    ///   - url: The file URL of the audio chunk to transcribe.
    ///   - locale: The locale indicating the expected language of the audio.
    /// - Returns: The best transcription as a formatted string.
    /// - Throws: `TranscriptionError` if the locale is unsupported, on-device
    ///   recognition is unavailable, or recognition fails.
    func transcribeFile(url: URL, locale: Locale) async throws -> String {
        let detail = try await transcribeFileWithSegments(url: url, locale: locale)
        return detail.formattedString
    }

    /// Transcribes an audio file returning word-level timing and pitch data.
    ///
    /// - Parameters:
    ///   - url: The file URL of the audio chunk to transcribe.
    ///   - locale: The locale indicating the expected language of the audio.
    /// - Returns: A `TranscriptionDetail` with formatted text and word segments.
    /// - Throws: `TranscriptionError` if recognition fails.
    /// Timeout for a single chunk transcription (2 minutes).
    private static let transcriptionTimeoutNs: UInt64 = 120_000_000_000

    func transcribeFileWithSegments(url: URL, locale: Locale) async throws -> TranscriptionDetail {
        let mode = RecognitionMode.load()

        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw TranscriptionError.unsupportedLocale
        }
        if mode.requiresOnDevice {
            guard recognizer.supportsOnDeviceRecognition else {
                throw TranscriptionError.onDeviceNotSupported
            }
        }

        return try await withThrowingTaskGroup(of: TranscriptionDetail.self) { group in
            // Actual recognition task
            group.addTask { [self] in
                try await recognizeOnce(
                    url: url,
                    recognizer: recognizer,
                    mode: mode
                )
            }

            // Timeout task
            group.addTask { [self] in
                try await Task.sleep(nanoseconds: Self.transcriptionTimeoutNs)
                cancelActiveRecognitionTask()
                throw TranscriptionError.recognitionFailed(
                    underlying: NSError(
                        domain: "OnDeviceTranscriber",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Transcription timed out"]
                    )
                )
            }

            // Return whichever finishes first; cancel the other
            let result: TranscriptionDetail
            do {
                result = try await group.next()!
            } catch {
                group.cancelAll()
                throw error
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Private Helpers

    private func recognizeOnce(
        url: URL,
        recognizer: SFSpeechRecognizer,
        mode: RecognitionMode
    ) async throws -> TranscriptionDetail {
        let startedAt = Date()
        let stateLock = NSLock()
        var task: SFSpeechRecognitionTask?
        var continuation: CheckedContinuation<TranscriptionDetail, Error>?
        var hasCompleted = false
        var mergedSegments: [MergedWordKey: WordSegmentInfo] = [:]
        var mergedConflictTexts: [MergedWordKey: Set<String>] = [:]

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<TranscriptionDetail, Error>) in
                let request = SFSpeechURLRecognitionRequest(url: url)
                request.requiresOnDeviceRecognition = mode.requiresOnDevice
                request.shouldReportPartialResults = true
                request.addsPunctuation = true
                request.taskHint = .dictation

                stateLock.withLock {
                    continuation = cont
                }

                task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    var completionResult: Result<TranscriptionDetail, Error>?

                    stateLock.withLock {
                        guard !hasCompleted else { return }

                        if let error {
                            hasCompleted = true
                            continuation = nil
                            task = nil
                            self?.setActiveRecognitionTask(nil)
                            completionResult = .failure(
                                TranscriptionError.recognitionFailed(underlying: error)
                            )
                            return
                        }

                        guard let result else { return }

                        Self.mergeSegments(
                            from: result.bestTranscription.segments,
                            into: &mergedSegments,
                            conflictTexts: &mergedConflictTexts
                        )

                        guard result.isFinal else { return }

                        let transcription = result.bestTranscription
                        let primaryWordSegments = transcription.segments.map(Self.mapSegmentToWordInfo)
                        let consensusWordSegments = Self.sortedMergedSegments(mergedSegments)
                        let consensusText = consensusWordSegments.map(\.substring).joined(separator: " ")
                        let conflictWordRate = Self.computeConflictWordRate(
                            conflictTexts: mergedConflictTexts
                        )

                        let resolved = Self.resolveFinalResultForTesting(
                            primaryText: transcription.formattedString,
                            primaryWordSegments: primaryWordSegments,
                            consensusText: consensusText,
                            consensusWordSegments: consensusWordSegments,
                            conflictWordRate: conflictWordRate
                        )

                        let diagnostics = Self.makeDiagnostics(
                            formattedString: resolved.text,
                            wordSegments: resolved.segments,
                            startedAt: startedAt,
                            textSource: resolved.source,
                            fallbackReason: resolved.reason,
                            qualitySignals: resolved.signals
                        )

                        hasCompleted = true
                        continuation = nil
                        task = nil
                        self?.setActiveRecognitionTask(nil)
                        completionResult = .success(
                            TranscriptionDetail(
                                formattedString: resolved.text,
                                wordSegments: resolved.segments,
                                diagnostics: diagnostics,
                                selectedTextSource: resolved.source,
                                qualitySignals: resolved.signals
                            )
                        )

                        if resolved.source == .consensusFallback {
                            self?.logger.warning(
                                "Using consensus fallback text due to primary truncation primaryLen=\(transcription.formattedString.count, privacy: .public) consensusLen=\(consensusText.count, privacy: .public) conflictRate=\(resolved.signals.conflictWordRate, privacy: .public) alignment=\(resolved.signals.alignmentScore, privacy: .public) reason=\(resolved.reason ?? "none", privacy: .public)"
                            )
                        } else if Self.normalizeText(consensusText).count
                            > Self.normalizeText(transcription.formattedString).count + 8 {
                            self?.logger.warning(
                                "Rejected consensus fallback to protect precision primaryLen=\(transcription.formattedString.count, privacy: .public) consensusLen=\(consensusText.count, privacy: .public) conflictRate=\(resolved.signals.conflictWordRate, privacy: .public) alignment=\(resolved.signals.alignmentScore, privacy: .public)"
                            )
                        }

                        self?.logger.info(
                            "URL recognition finished textLen=\(diagnostics.textLength, privacy: .public) wordCount=\(diagnostics.wordCount, privacy: .public) durationMs=\(diagnostics.recognitionDurationMs, privacy: .public)"
                        )
                    }

                    guard let completionResult else { return }
                    cont.resume(with: completionResult)
                }
                self.setActiveRecognitionTask(task)
            }
        }, onCancel: {
            var cancellationContinuation: CheckedContinuation<TranscriptionDetail, Error>?

            stateLock.withLock {
                task?.cancel()
                task = nil
                self.setActiveRecognitionTask(nil)

                guard !hasCompleted else { return }
                hasCompleted = true
                cancellationContinuation = continuation
                continuation = nil
            }

            cancellationContinuation?.resume(throwing: CancellationError())
        })
    }

    private func setActiveRecognitionTask(_ task: SFSpeechRecognitionTask?) {
        activeTaskLock.withLock {
            activeRecognitionTask = task
        }
    }

    private func cancelActiveRecognitionTask() {
        activeTaskLock.withLock {
            activeRecognitionTask?.cancel()
            activeRecognitionTask = nil
        }
    }

    private static func mapSegmentToWordInfo(
        _ seg: SFTranscriptionSegment
    ) -> WordSegmentInfo {
        let analytics = seg.voiceAnalytics

        return WordSegmentInfo(
            substring: seg.substring,
            timestamp: seg.timestamp,
            duration: seg.duration,
            confidence: seg.confidence,
            averagePitch: extractAveragePitch(from: seg),
            pitchStdDev: extractStdDev(from: analytics?.pitch),
            averageEnergy: nil,           // Not available in voiceAnalytics; AudioFeatureExtractor fills this
            averageSpectralCentroid: nil,  // Same — filled by AudioFeatureExtractor
            averageJitter: extractAverage(from: analytics?.jitter),
            averageShimmer: extractAverage(from: analytics?.shimmer)
        )
    }

    private static func extractAveragePitch(
        from seg: SFTranscriptionSegment
    ) -> Float? {
        guard let voiceAnalytics = seg.voiceAnalytics else { return nil }
        let pitchValues = voiceAnalytics.pitch.acousticFeatureValuePerFrame
        guard !pitchValues.isEmpty else { return nil }

        let sum = pitchValues.reduce(0.0) { $0 + Double($1) }
        let avg = Float(sum / Double(pitchValues.count))

        // Filter out clearly invalid values
        guard avg > 0, avg.isFinite else { return nil }
        return avg
    }

    /// Extracts the mean value from an `SFAcousticFeature`.
    private static func extractAverage(from feature: SFAcousticFeature?) -> Float? {
        guard let feature = feature else { return nil }
        let values = feature.acousticFeatureValuePerFrame
        guard !values.isEmpty else { return nil }
        let sum = values.reduce(0.0) { $0 + Double($1) }
        let avg = Float(sum / Double(values.count))
        guard avg.isFinite else { return nil }
        return avg
    }

    /// Extracts the standard deviation from an `SFAcousticFeature`.
    private static func extractStdDev(from feature: SFAcousticFeature?) -> Float? {
        guard let feature = feature else { return nil }
        let values = feature.acousticFeatureValuePerFrame
        guard values.count > 1 else { return nil }
        let sum = values.reduce(0.0) { $0 + Double($1) }
        let mean = sum / Double(values.count)
        let variance = values.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(values.count)
        let stdDev = Float(sqrt(variance))
        guard stdDev.isFinite else { return nil }
        return stdDev
    }

    private static func makeDiagnostics(
        formattedString: String,
        wordSegments: [WordSegmentInfo],
        startedAt: Date,
        textSource: TranscriptionTextSource,
        fallbackReason: String?,
        qualitySignals: TranscriptionQualitySignals
    ) -> TranscriptionDiagnostics {
        let firstWordStartMs = wordSegments.min { $0.timestamp < $1.timestamp }.map {
            Int64($0.timestamp * 1000)
        }
        let lastWordEndMs = wordSegments.max {
            ($0.timestamp + $0.duration) < ($1.timestamp + $1.duration)
        }.map {
            Int64(($0.timestamp + $0.duration) * 1000)
        }

        return TranscriptionDiagnostics(
            textLength: formattedString.count,
            wordCount: wordSegments.count,
            firstWordStartMs: firstWordStartMs,
            lastWordEndMs: lastWordEndMs,
            recognitionDurationMs: Int64(Date().timeIntervalSince(startedAt) * 1000),
            textSource: textSource,
            fallbackReason: fallbackReason,
            conflictWordRate: qualitySignals.conflictWordRate,
            alignmentScore: qualitySignals.alignmentScore
        )
    }

    private struct MergedWordKey: Hashable {
        let startBucketMs: Int64
        let durationBucketMs: Int64
    }

    private static func mergeSegments(
        from segments: [SFTranscriptionSegment],
        into merged: inout [MergedWordKey: WordSegmentInfo],
        conflictTexts: inout [MergedWordKey: Set<String>]
    ) {
        for seg in segments {
            let normalizedText = normalizeText(seg.substring)
            if normalizedText.isEmpty { continue }
            let key = makeMergedWordKey(seg)
            let mapped = mapSegmentToWordInfo(seg)
            conflictTexts[key, default: []].insert(normalizedText)
            if let existing = merged[key] {
                if mapped.confidence >= existing.confidence {
                    merged[key] = mapped
                }
            } else {
                merged[key] = mapped
            }
        }
    }

    private static func makeMergedWordKey(_ segment: SFTranscriptionSegment) -> MergedWordKey {
        let bucketMs: Double = 100
        let startMs = segment.timestamp * 1000
        let durationMs = segment.duration * 1000
        let startBucket = Int64((startMs / bucketMs).rounded() * bucketMs)
        let durationBucket = Int64((durationMs / bucketMs).rounded() * bucketMs)
        return MergedWordKey(
            startBucketMs: startBucket,
            durationBucketMs: max(100, durationBucket)
        )
    }

    private static func sortedMergedSegments(
        _ merged: [MergedWordKey: WordSegmentInfo]
    ) -> [WordSegmentInfo] {
        merged.values.sorted {
            if $0.timestamp == $1.timestamp {
                return $0.duration < $1.duration
            }
            return $0.timestamp < $1.timestamp
        }
    }

    private static func computeConflictWordRate(
        conflictTexts: [MergedWordKey: Set<String>]
    ) -> Double {
        guard !conflictTexts.isEmpty else { return 0 }
        let conflicting = conflictTexts.values.reduce(0) { count, set in
            count + (set.count > 1 ? 1 : 0)
        }
        return Double(conflicting) / Double(conflictTexts.count)
    }

    static func resolveFinalResultForTesting(
        primaryText: String,
        primaryWordSegments: [WordSegmentInfo],
        consensusText: String,
        consensusWordSegments: [WordSegmentInfo],
        conflictWordRate: Double
    ) -> (
        text: String,
        segments: [WordSegmentInfo],
        source: TranscriptionTextSource,
        signals: TranscriptionQualitySignals,
        reason: String?
    ) {
        let normalizedPrimary = normalizeText(primaryText)
        let normalizedConsensus = normalizeText(consensusText)

        let primaryLen = normalizedPrimary.count
        let consensusLen = normalizedConsensus.count
        let primaryCoverage = consensusLen == 0 ? 1.0 : Double(primaryLen) / Double(consensusLen)
        let alignmentScore = diceCoefficient(normalizedPrimary, normalizedConsensus)
        let signals = TranscriptionQualitySignals(
            primaryCoverage: primaryCoverage,
            alignmentScore: alignmentScore,
            conflictWordRate: conflictWordRate,
            primaryWordCount: primaryWordSegments.count,
            consensusWordCount: consensusWordSegments.count
        )

        guard !normalizedPrimary.isEmpty else {
            if !normalizedConsensus.isEmpty {
                return (
                    text: consensusText,
                    segments: consensusWordSegments,
                    source: .consensusFallback,
                    signals: signals,
                    reason: "primary_empty"
                )
            }
            return (
                text: primaryText,
                segments: primaryWordSegments,
                source: .primaryFinal,
                signals: signals,
                reason: nil
            )
        }

        guard !normalizedConsensus.isEmpty else {
            return (
                text: primaryText,
                segments: primaryWordSegments,
                source: .primaryFinal,
                signals: signals,
                reason: nil
            )
        }

        if shouldUseConsensusFallback(
            signals: signals,
            primaryLength: primaryLen,
            consensusLength: consensusLen
        ) {
            return (
                text: consensusText,
                segments: consensusWordSegments,
                source: .consensusFallback,
                signals: signals,
                reason: "primary_truncation_high_alignment_low_conflict"
            )
        }
        return (
            text: primaryText,
            segments: primaryWordSegments,
            source: .primaryFinal,
            signals: signals,
            reason: nil
        )
    }

    private static func shouldUseConsensusFallback(
        signals: TranscriptionQualitySignals,
        primaryLength: Int,
        consensusLength: Int
    ) -> Bool {
        guard consensusLength >= 12 else { return false }
        guard consensusLength > primaryLength else { return false }
        guard signals.consensusWordCount >= signals.primaryWordCount else { return false }
        guard signals.primaryCoverage < 0.45 else { return false }
        guard signals.alignmentScore >= 0.88 else { return false }
        guard signals.conflictWordRate <= 0.08 else { return false }
        return true
    }

    private static func diceCoefficient(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs { return 1.0 }
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0.0 }

        let lhsGrams = bigrams(lhs)
        let rhsGrams = bigrams(rhs)
        guard !lhsGrams.isEmpty, !rhsGrams.isEmpty else {
            return lhs == rhs ? 1.0 : 0.0
        }

        var rhsCounts: [String: Int] = [:]
        for gram in rhsGrams {
            rhsCounts[gram, default: 0] += 1
        }

        var intersection = 0
        for gram in lhsGrams {
            guard let count = rhsCounts[gram], count > 0 else { continue }
            intersection += 1
            rhsCounts[gram] = count - 1
        }

        return (2.0 * Double(intersection)) / Double(lhsGrams.count + rhsGrams.count)
    }

    private static func bigrams(_ text: String) -> [String] {
        let chars = Array(text)
        guard chars.count >= 2 else { return [] }
        var grams: [String] = []
        grams.reserveCapacity(chars.count - 1)
        for idx in 0..<(chars.count - 1) {
            grams.append(String([chars[idx], chars[idx + 1]]))
        }
        return grams
    }

    private static func normalizeText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
