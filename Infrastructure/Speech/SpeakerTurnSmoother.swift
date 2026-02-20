import Foundation

/// Post-processing smoother for speaker diarization output.
///
/// Applies four sequential passes to clean up noisy segment boundaries:
/// 1. **Minimum duration**: Merges segments shorter than `minDurationMs` into neighbors.
/// 2. **Collar merge**: Merges segments separated by gaps shorter than `collarMs`.
/// 3. **Isolated turn removal**: Removes very short turns (< 1s) surrounded by the same speaker.
/// 4. **Consecutive merge**: Merges adjacent segments from the same speaker.
enum SpeakerTurnSmoother {

    /// A speaker-attributed time segment.
    struct SpeakerSegment: Equatable {
        let startFrame: Int
        let endFrame: Int
        let speakerLabel: Int

        var durationFrames: Int { endFrame - startFrame }

        func durationMs(frameHopMs: Int) -> Int {
            durationFrames * frameHopMs
        }
    }

    // MARK: - Public API

    /// Smooths a sequence of speaker segments through four cleaning passes.
    ///
    /// - Parameters:
    ///   - segments: Input speaker segments (sorted by time).
    ///   - minDurationMs: Minimum segment duration in milliseconds (default 500).
    ///   - collarMs: Collar gap for merging in milliseconds (default 300).
    ///   - frameHopMs: Duration of one frame hop in milliseconds (default 10).
    /// - Returns: Cleaned, merged speaker segments.
    static func smooth(
        segments: [SpeakerSegment],
        minDurationMs: Int = 500,
        collarMs: Int = 300,
        frameHopMs: Int = 10
    ) -> [SpeakerSegment] {
        guard segments.count > 1 else { return segments }

        // Pass 1: Minimum duration enforcement
        let pass1 = enforceMinDuration(
            segments: segments,
            minDurationMs: minDurationMs,
            frameHopMs: frameHopMs
        )

        // Pass 2: Collar merge
        let pass2 = collarMerge(
            segments: pass1,
            collarMs: collarMs,
            frameHopMs: frameHopMs
        )

        // Pass 3: Isolated turn removal
        let pass3 = removeIsolatedTurns(
            segments: pass2,
            maxIsolatedMs: 1000,
            frameHopMs: frameHopMs
        )

        // Pass 4: Merge consecutive same-speaker
        return mergeConsecutive(segments: pass3)
    }

    // MARK: - Pass 1: Minimum Duration

    static func enforceMinDuration(
        segments: [SpeakerSegment],
        minDurationMs: Int,
        frameHopMs: Int
    ) -> [SpeakerSegment] {
        guard segments.count > 1 else { return segments }

        var result = segments

        var changed = true
        var iterations = 0
        let maxIterations = result.count

        while changed, iterations < maxIterations {
            changed = false
            iterations += 1

            var newResult: [SpeakerSegment] = []
            for seg in result {
                if seg.durationMs(frameHopMs: frameHopMs) < minDurationMs, !newResult.isEmpty {
                    // Merge into previous segment
                    let prev = newResult.removeLast()
                    newResult.append(SpeakerSegment(
                        startFrame: prev.startFrame,
                        endFrame: seg.endFrame,
                        speakerLabel: prev.speakerLabel
                    ))
                    changed = true
                } else {
                    newResult.append(seg)
                }
            }
            result = newResult
        }

        return result
    }

    // MARK: - Pass 2: Collar Merge

    static func collarMerge(
        segments: [SpeakerSegment],
        collarMs: Int,
        frameHopMs: Int
    ) -> [SpeakerSegment] {
        guard segments.count > 1 else { return segments }
        let collarFrames = collarMs / max(1, frameHopMs)

        var result: [SpeakerSegment] = [segments[0]]

        for i in 1..<segments.count {
            let prev = result[result.count - 1]
            let curr = segments[i]

            let gap = curr.startFrame - prev.endFrame

            // If gap is within collar and same speaker, merge
            if gap <= collarFrames, prev.speakerLabel == curr.speakerLabel {
                result[result.count - 1] = SpeakerSegment(
                    startFrame: prev.startFrame,
                    endFrame: curr.endFrame,
                    speakerLabel: prev.speakerLabel
                )
            } else {
                result.append(curr)
            }
        }

        return result
    }

    // MARK: - Pass 3: Isolated Turn Removal

    static func removeIsolatedTurns(
        segments: [SpeakerSegment],
        maxIsolatedMs: Int,
        frameHopMs: Int
    ) -> [SpeakerSegment] {
        guard segments.count > 2 else { return segments }

        var result: [SpeakerSegment] = []

        for i in 0..<segments.count {
            let seg = segments[i]
            let isShort = seg.durationMs(frameHopMs: frameHopMs) < maxIsolatedMs

            if isShort, i > 0, i < segments.count - 1 {
                let prev = segments[i - 1]
                let next = segments[i + 1]

                // If surrounded by the same speaker, absorb into previous
                if prev.speakerLabel == next.speakerLabel {
                    if !result.isEmpty {
                        let last = result.removeLast()
                        result.append(SpeakerSegment(
                            startFrame: last.startFrame,
                            endFrame: seg.endFrame,
                            speakerLabel: last.speakerLabel
                        ))
                    }
                    continue
                }
            }

            result.append(seg)
        }

        return result
    }

    // MARK: - Pass 4: Merge Consecutive Same Speaker

    static func mergeConsecutive(segments: [SpeakerSegment]) -> [SpeakerSegment] {
        guard !segments.isEmpty else { return [] }

        var result: [SpeakerSegment] = [segments[0]]

        for i in 1..<segments.count {
            let curr = segments[i]
            let lastIdx = result.count - 1

            if result[lastIdx].speakerLabel == curr.speakerLabel {
                result[lastIdx] = SpeakerSegment(
                    startFrame: result[lastIdx].startFrame,
                    endFrame: curr.endFrame,
                    speakerLabel: curr.speakerLabel
                )
            } else {
                result.append(curr)
            }
        }

        return result
    }
}
