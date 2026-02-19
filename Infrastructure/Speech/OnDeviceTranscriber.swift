import Foundation
import Speech

/// Detailed transcription result containing both formatted text and word-level data.
struct TranscriptionDetail {
    let formattedString: String
    let wordSegments: [WordSegmentInfo]
}

/// On-device speech transcription using Apple's Speech framework.
///
/// Uses `SFSpeechURLRecognitionRequest` with `requiresOnDeviceRecognition = true`
/// so that audio data never leaves the device. This satisfies privacy requirements
/// but limits support to languages that have on-device models downloaded.
final class OnDeviceTranscriber: TranscriptionServiceProtocol {

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
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    let request = SFSpeechURLRecognitionRequest(url: url)
                    request.requiresOnDeviceRecognition = mode.requiresOnDevice
                    request.shouldReportPartialResults = false
                    request.addsPunctuation = true
                    request.taskHint = .dictation

                    var hasResumed = false

                    recognizer.recognitionTask(with: request) { result, error in
                        guard !hasResumed else { return }

                        if let error = error {
                            hasResumed = true
                            continuation.resume(
                                throwing: TranscriptionError.recognitionFailed(underlying: error)
                            )
                            return
                        }

                        if let result = result, result.isFinal {
                            hasResumed = true

                            let transcription = result.bestTranscription
                            let wordSegments = transcription.segments.map { seg in
                                Self.mapSegmentToWordInfo(seg)
                            }

                            let detail = TranscriptionDetail(
                                formattedString: transcription.formattedString,
                                wordSegments: wordSegments
                            )
                            continuation.resume(returning: detail)
                        }
                    }
                }
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: Self.transcriptionTimeoutNs)
                throw TranscriptionError.recognitionFailed(
                    underlying: NSError(
                        domain: "OnDeviceTranscriber",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Transcription timed out"]
                    )
                )
            }

            // Return whichever finishes first; cancel the other
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Private Helpers

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
}
