import Foundation

/// Maps transcribed words to speaker labels using time overlap with diarization segments.
///
/// Each word is assigned to the speaker segment with which it has the greatest
/// temporal overlap. If a word falls entirely outside all segments, it is
/// assigned to the nearest segment as a fallback.
enum WordSpeakerMapper {

    /// A word paired with its assigned speaker label.
    struct MappedWord {
        let word: WordSegmentInfo
        let speakerLabel: Int
    }

    // MARK: - Public API

    /// Maps each word to a speaker label based on temporal overlap with speaker segments.
    ///
    /// - Parameters:
    ///   - words: Transcribed words with timestamps.
    ///   - segments: Speaker-attributed time segments (frame-based).
    ///   - frameHopSec: Duration of one frame hop in seconds (default 0.01).
    /// - Returns: Array of words paired with speaker labels, in input order.
    static func mapWords(
        words: [WordSegmentInfo],
        segments: [SpeakerTurnSmoother.SpeakerSegment],
        frameHopSec: Float = 0.01
    ) -> [MappedWord] {
        guard !segments.isEmpty else {
            return words.map { MappedWord(word: $0, speakerLabel: 0) }
        }

        return words.map { word in
            let label = findBestSegment(
                wordStart: Float(word.timestamp),
                wordEnd: Float(word.timestamp + word.duration),
                segments: segments,
                frameHopSec: frameHopSec
            )
            return MappedWord(word: word, speakerLabel: label)
        }
    }

    // MARK: - Internal

    static func findBestSegment(
        wordStart: Float,
        wordEnd: Float,
        segments: [SpeakerTurnSmoother.SpeakerSegment],
        frameHopSec: Float
    ) -> Int {
        var bestOverlap: Float = 0
        var bestLabel = segments[0].speakerLabel

        for seg in segments {
            let segStart = Float(seg.startFrame) * frameHopSec
            let segEnd = Float(seg.endFrame) * frameHopSec

            let overlapStart = max(wordStart, segStart)
            let overlapEnd = min(wordEnd, segEnd)
            let overlap = max(0, overlapEnd - overlapStart)

            if overlap > bestOverlap {
                bestOverlap = overlap
                bestLabel = seg.speakerLabel
            }
        }

        // Fallback: if no overlap, find nearest segment
        if bestOverlap <= 0 {
            bestLabel = findNearestSegment(
                wordMid: (wordStart + wordEnd) / 2,
                segments: segments,
                frameHopSec: frameHopSec
            )
        }

        return bestLabel
    }

    private static func findNearestSegment(
        wordMid: Float,
        segments: [SpeakerTurnSmoother.SpeakerSegment],
        frameHopSec: Float
    ) -> Int {
        var minDistance: Float = .infinity
        var nearestLabel = segments[0].speakerLabel

        for seg in segments {
            let segMid = Float(seg.startFrame + seg.endFrame) / 2 * frameHopSec
            let dist = abs(wordMid - segMid)

            if dist < minDistance {
                minDistance = dist
                nearestLabel = seg.speakerLabel
            }
        }

        return nearestLabel
    }
}
