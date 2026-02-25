import Foundation

/// Result of completeness checks between full transcription text and diarized output.
struct TranscriptionCompletenessEvaluation {
    let isSuspectTruncation: Bool
    let shouldFallbackToFullText: Bool
    let reason: String?
    let fullTextLength: Int
    let diarizedTextLength: Int
    let wordSpanMs: Int64?
    let diarizedSpanMs: Int64?
}

/// Evaluates whether diarized segments look incomplete compared to full transcription text.
///
/// The goal is defensive: if diarization output appears truncated, preserve full text rather
/// than risking partial transcript persistence.
enum TranscriptionCompletenessEvaluator {

    private enum Threshold {
        static let minFullTextLengthForLengthRatio = 20
        static let minShortfallChars = 12
        static let minDiarizedToFullLengthRatio = 0.55
        static let minWordSpanMsForCoverageCheck: Int64 = 10_000
        static let minDiarizedCoverageRatio = 0.55
    }

    static func evaluate(
        fullText: String,
        wordSegments: [WordSegmentInfo],
        diarizedSegments: [DiarizedSegment],
        chunkDurationSec: Double
    ) -> TranscriptionCompletenessEvaluation {
        let normalizedFullText = normalize(fullText)
        let normalizedDiarizedText = normalize(
            diarizedSegments
                .map(\.text)
                .joined(separator: " ")
        )

        let wordSpanMs = computeWordSpanMs(wordSegments: wordSegments)
        let diarizedSpanMs = computeDiarizedSpanMs(segments: diarizedSegments)

        guard !normalizedFullText.isEmpty else {
            return TranscriptionCompletenessEvaluation(
                isSuspectTruncation: false,
                shouldFallbackToFullText: false,
                reason: nil,
                fullTextLength: 0,
                diarizedTextLength: normalizedDiarizedText.count,
                wordSpanMs: wordSpanMs,
                diarizedSpanMs: diarizedSpanMs
            )
        }

        if normalizedDiarizedText.isEmpty {
            return TranscriptionCompletenessEvaluation(
                isSuspectTruncation: true,
                shouldFallbackToFullText: true,
                reason: "diarized_text_empty",
                fullTextLength: normalizedFullText.count,
                diarizedTextLength: 0,
                wordSpanMs: wordSpanMs,
                diarizedSpanMs: diarizedSpanMs
            )
        }

        let fullLength = normalizedFullText.count
        let diarizedLength = normalizedDiarizedText.count
        let lengthRatio = Double(diarizedLength) / Double(max(1, fullLength))
        let lengthShortfall = fullLength - diarizedLength

        if fullLength >= Threshold.minFullTextLengthForLengthRatio,
           lengthShortfall >= Threshold.minShortfallChars,
           lengthRatio < Threshold.minDiarizedToFullLengthRatio {
            return TranscriptionCompletenessEvaluation(
                isSuspectTruncation: true,
                shouldFallbackToFullText: true,
                reason: "diarized_text_much_shorter_than_full_text",
                fullTextLength: fullLength,
                diarizedTextLength: diarizedLength,
                wordSpanMs: wordSpanMs,
                diarizedSpanMs: diarizedSpanMs
            )
        }

        if let wordSpanMs,
           let diarizedSpanMs,
           wordSpanMs >= Threshold.minWordSpanMsForCoverageCheck {
            let coverageRatio = Double(diarizedSpanMs) / Double(max(1, wordSpanMs))

            if coverageRatio < Threshold.minDiarizedCoverageRatio {
                return TranscriptionCompletenessEvaluation(
                    isSuspectTruncation: true,
                    shouldFallbackToFullText: true,
                    reason: "diarized_time_coverage_too_small",
                    fullTextLength: fullLength,
                    diarizedTextLength: diarizedLength,
                    wordSpanMs: wordSpanMs,
                    diarizedSpanMs: diarizedSpanMs
                )
            }
        }

        // Very long chunk with very short diarized text is suspicious even without timestamps.
        if chunkDurationSec >= 20,
           fullLength >= Threshold.minFullTextLengthForLengthRatio,
           diarizedLength <= 8 {
            return TranscriptionCompletenessEvaluation(
                isSuspectTruncation: true,
                shouldFallbackToFullText: true,
                reason: "chunk_long_but_diarized_text_too_short",
                fullTextLength: fullLength,
                diarizedTextLength: diarizedLength,
                wordSpanMs: wordSpanMs,
                diarizedSpanMs: diarizedSpanMs
            )
        }

        return TranscriptionCompletenessEvaluation(
            isSuspectTruncation: false,
            shouldFallbackToFullText: false,
            reason: nil,
            fullTextLength: fullLength,
            diarizedTextLength: diarizedLength,
            wordSpanMs: wordSpanMs,
            diarizedSpanMs: diarizedSpanMs
        )
    }

    private static func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func computeWordSpanMs(wordSegments: [WordSegmentInfo]) -> Int64? {
        guard !wordSegments.isEmpty else { return nil }
        guard let firstStart = wordSegments.min(by: { $0.timestamp < $1.timestamp })?.timestamp else {
            return nil
        }
        guard let lastEnd = wordSegments.max(by: {
            ($0.timestamp + $0.duration) < ($1.timestamp + $1.duration)
        }).map({ $0.timestamp + $0.duration }) else {
            return nil
        }

        let span = Int64((lastEnd - firstStart) * 1000)
        return max(0, span)
    }

    private static func computeDiarizedSpanMs(segments: [DiarizedSegment]) -> Int64? {
        guard !segments.isEmpty else { return nil }
        guard let firstStart = segments.min(by: { $0.startOffsetMs < $1.startOffsetMs })?.startOffsetMs else {
            return nil
        }
        guard let lastEnd = segments.max(by: { $0.endOffsetMs < $1.endOffsetMs })?.endOffsetMs else {
            return nil
        }

        return max(0, lastEnd - firstStart)
    }
}
