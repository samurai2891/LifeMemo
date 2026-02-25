import Foundation
import Speech
import os.log

/// Detailed transcription result containing both formatted text and word-level data.
struct TranscriptionDetail {
    let formattedString: String
    let wordSegments: [WordSegmentInfo]
    let diagnostics: TranscriptionDiagnostics

    init(
        formattedString: String,
        wordSegments: [WordSegmentInfo],
        diagnostics: TranscriptionDiagnostics? = nil
    ) {
        self.formattedString = formattedString
        self.wordSegments = wordSegments
        self.diagnostics = diagnostics ?? TranscriptionDiagnostics(
            textLength: formattedString.count,
            wordCount: wordSegments.count,
            firstWordStartMs: wordSegments.first.map { Int64($0.timestamp * 1000) },
            lastWordEndMs: wordSegments.last.map { Int64(($0.timestamp + $0.duration) * 1000) },
            recognitionDurationMs: 0
        )
    }
}

/// Diagnostics captured from one URL-based recognition request.
struct TranscriptionDiagnostics {
    let textLength: Int
    let wordCount: Int
    let firstWordStartMs: Int64?
    let lastWordEndMs: Int64?
    let recognitionDurationMs: Int64
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
                            into: &mergedSegments
                        )

                        guard result.isFinal else { return }

                        let transcription = result.bestTranscription
                        let wordSegments = Self.sortedMergedSegments(mergedSegments)
                        let mergedText = wordSegments.map(\.substring).joined(separator: " ")
                        let resolvedText = Self.resolveFormattedString(
                            primary: transcription.formattedString,
                            mergedFallback: mergedText
                        )

                        let diagnostics = Self.makeDiagnostics(
                            formattedString: resolvedText,
                            wordSegments: wordSegments,
                            startedAt: startedAt
                        )

                        hasCompleted = true
                        continuation = nil
                        task = nil
                        self?.setActiveRecognitionTask(nil)
                        completionResult = .success(
                            TranscriptionDetail(
                                formattedString: resolvedText,
                                wordSegments: wordSegments,
                                diagnostics: diagnostics
                            )
                        )

                        if Self.normalizeText(resolvedText).count
                            > Self.normalizeText(transcription.formattedString).count + 8 {
                            self?.logger.warning(
                                "Using merged URL transcription text due to possible truncation primaryLen=\(transcription.formattedString.count, privacy: .public) mergedLen=\(resolvedText.count, privacy: .public)"
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
        startedAt: Date
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
            recognitionDurationMs: Int64(Date().timeIntervalSince(startedAt) * 1000)
        )
    }

    private struct MergedWordKey: Hashable {
        let startBucketMs: Int64
        let durationBucketMs: Int64
        let substring: String
    }

    private static func mergeSegments(
        from segments: [SFTranscriptionSegment],
        into merged: inout [MergedWordKey: WordSegmentInfo]
    ) {
        for seg in segments {
            if normalizeText(seg.substring).isEmpty { continue }
            let key = makeMergedWordKey(seg)
            let mapped = mapSegmentToWordInfo(seg)
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
        let text = normalizeText(segment.substring)
        return MergedWordKey(
            startBucketMs: startBucket,
            durationBucketMs: max(100, durationBucket),
            substring: text
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

    private static func resolveFormattedString(
        primary: String,
        mergedFallback: String
    ) -> String {
        let normalizedPrimary = normalizeText(primary)
        let normalizedMerged = normalizeText(mergedFallback)

        guard !normalizedPrimary.isEmpty else { return mergedFallback }
        guard !normalizedMerged.isEmpty else { return primary }

        let primaryLen = normalizedPrimary.count
        let mergedLen = normalizedMerged.count
        let primaryCoverage = Double(primaryLen) / Double(max(1, mergedLen))

        if mergedLen >= 10, primaryCoverage < 0.70 {
            return mergedFallback
        }
        return primary
    }

    private static func normalizeText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
