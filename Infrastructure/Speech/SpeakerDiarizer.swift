import Foundation

/// MFCC-based speaker diarization pipeline.
///
/// Replaces the previous score-based change point detector with a statistically
/// grounded 7-step pipeline:
///
/// 1. Audio → MFCC extraction (13 coefficients + delta + delta-delta)
/// 2. Energy-based Voice Activity Detection
/// 3. BIC segmentation (speaker change point detection)
/// 4. Segment embedding generation (130D)
/// 5. Agglomerative Hierarchical Clustering
/// 6. Post-processing smoothing
/// 7. Word → speaker mapping
///
/// The public API signature is unchanged so callers (`TranscriptionQueueActor`,
/// `AppContainer`) require no modifications.
final class SpeakerDiarizer {

    // MARK: - Public API

    /// Diarizes word segments into speaker-attributed turns.
    ///
    /// - Parameters:
    ///   - audioURL: File URL of the audio chunk.
    ///   - wordSegments: Word-level data from the transcriber.
    /// - Returns: A `DiarizationResult` with speaker-labelled segments and profiles.
    func diarize(audioURL: URL, wordSegments: [WordSegmentInfo]) -> DiarizationResult {
        guard !wordSegments.isEmpty else {
            return DiarizationResult(segments: [], speakerCount: 0)
        }

        // Step 1: Read audio and extract MFCCs
        guard let audio = MelFilterbank.readSamples(url: audioURL) else {
            return makeSingleSpeakerResult(wordSegments: wordSegments)
        }

        let mfccResult = MelFilterbank.extractMFCCs(
            samples: audio.samples,
            sampleRate: audio.sampleRate
        )

        guard !mfccResult.mfccs.isEmpty else {
            return makeSingleSpeakerResult(wordSegments: wordSegments)
        }

        // Step 2: Voice Activity Detection
        let speechRegions = EnergyVAD.detectSpeechRegions(rmsEnergies: mfccResult.rmsEnergies)

        guard !speechRegions.isEmpty else {
            return makeSingleSpeakerResult(wordSegments: wordSegments)
        }

        // Step 3: BIC segmentation
        let boundaries = BICSegmenter.segment(
            mfccFrames: mfccResult.mfccs,
            speechRegions: speechRegions
        )

        // Build segment ranges from boundaries + speech regions
        let segmentRanges = buildSegmentRanges(
            speechRegions: speechRegions,
            boundaries: boundaries,
            totalFrames: mfccResult.mfccs.count
        )

        guard segmentRanges.count > 1 else {
            return makeSingleSpeakerResult(wordSegments: wordSegments, mfccResult: mfccResult)
        }

        // Step 4: Generate embeddings for each segment
        let embeddings: [SpeakerEmbedding] = segmentRanges.compactMap { range in
            let startFrame = range.startFrame
            let endFrame = min(range.endFrame, mfccResult.mfccs.count)
            guard endFrame > startFrame else { return nil }

            let mfccSlice = Array(mfccResult.mfccs[startFrame..<endFrame])
            let deltaSlice = Array(mfccResult.deltas[startFrame..<endFrame])
            let ddSlice = Array(mfccResult.deltaDeltas[startFrame..<endFrame])

            return SegmentEmbedder.computeEmbedding(
                mfccFrames: mfccSlice,
                deltas: deltaSlice,
                deltaDeltas: ddSlice
            )
        }

        guard embeddings.count > 1 else {
            return makeSingleSpeakerResult(wordSegments: wordSegments, mfccResult: mfccResult)
        }

        // Step 5: AHC clustering
        let clusterResult = AHCClusterer.cluster(embeddings: embeddings)

        guard clusterResult.numClusters > 1 else {
            return makeSingleSpeakerResult(wordSegments: wordSegments, mfccResult: mfccResult)
        }

        // Build speaker segments from cluster labels
        var speakerSegments: [SpeakerTurnSmoother.SpeakerSegment] = []
        for (i, range) in segmentRanges.enumerated() {
            let label = i < clusterResult.labels.count ? clusterResult.labels[i] : 0
            speakerSegments.append(SpeakerTurnSmoother.SpeakerSegment(
                startFrame: range.startFrame,
                endFrame: range.endFrame,
                speakerLabel: label
            ))
        }

        // Step 6: Post-processing smoothing
        let smoothed = SpeakerTurnSmoother.smooth(segments: speakerSegments)

        // Step 7: Word → speaker mapping
        let mappedWords = WordSpeakerMapper.mapWords(
            words: wordSegments,
            segments: smoothed
        )

        // Build DiarizationResult
        return buildResult(
            mappedWords: mappedWords,
            smoothedSegments: smoothed,
            segmentRanges: segmentRanges,
            clusterResult: clusterResult,
            embeddings: embeddings,
            mfccResult: mfccResult
        )
    }

    // MARK: - Segment Range Building

    private struct SegmentRange {
        let startFrame: Int
        let endFrame: Int
    }

    private func buildSegmentRanges(
        speechRegions: [EnergyVAD.SpeechRegion],
        boundaries: [BICSegmenter.Boundary],
        totalFrames: Int
    ) -> [SegmentRange] {
        // Collect all boundary frame indices
        let boundaryFrames = Set(boundaries.map(\.frameIndex))

        var ranges: [SegmentRange] = []

        for region in speechRegions {
            var segStart = region.startFrame

            // Find boundaries within this speech region
            let regionBoundaries = boundaries
                .filter { $0.frameIndex > region.startFrame && $0.frameIndex < region.endFrame }
                .sorted { $0.frameIndex < $1.frameIndex }

            for boundary in regionBoundaries {
                if boundary.frameIndex > segStart {
                    ranges.append(SegmentRange(
                        startFrame: segStart,
                        endFrame: boundary.frameIndex
                    ))
                    segStart = boundary.frameIndex
                }
            }

            // Final segment in this region
            if segStart < region.endFrame {
                ranges.append(SegmentRange(
                    startFrame: segStart,
                    endFrame: region.endFrame
                ))
            }
        }

        return ranges
    }

    // MARK: - Result Building

    private func buildResult(
        mappedWords: [WordSpeakerMapper.MappedWord],
        smoothedSegments: [SpeakerTurnSmoother.SpeakerSegment],
        segmentRanges: [SegmentRange],
        clusterResult: AHCClusterer.ClusterResult,
        embeddings: [SpeakerEmbedding],
        mfccResult: MelFilterbank.MFCCResult
    ) -> DiarizationResult {
        // Group consecutive words by speaker
        var diarizedSegments: [DiarizedSegment] = []
        var currentWords: [WordSegmentInfo] = []
        var currentSpeaker = -1

        for mapped in mappedWords {
            if mapped.speakerLabel != currentSpeaker {
                if !currentWords.isEmpty {
                    diarizedSegments.append(makeDiarizedSegment(
                        words: currentWords,
                        speakerIndex: currentSpeaker
                    ))
                }
                currentWords = [mapped.word]
                currentSpeaker = mapped.speakerLabel
            } else {
                currentWords.append(mapped.word)
            }
        }

        if !currentWords.isEmpty {
            diarizedSegments.append(makeDiarizedSegment(
                words: currentWords,
                speakerIndex: currentSpeaker
            ))
        }

        let speakerIndices = Set(diarizedSegments.map(\.speakerIndex))
        let speakerCount = speakerIndices.count

        // Build speaker profiles with MFCC embeddings
        let profiles = buildSpeakerProfiles(
            speakerLabels: Array(speakerIndices).sorted(),
            clusterLabels: clusterResult.labels,
            embeddings: embeddings
        )

        return DiarizationResult(
            segments: diarizedSegments,
            speakerCount: speakerCount,
            speakerProfiles: profiles
        )
    }

    private func makeDiarizedSegment(
        words: [WordSegmentInfo],
        speakerIndex: Int
    ) -> DiarizedSegment {
        let text = words.map(\.substring).joined(separator: " ")
        let start = Int64(words[0].timestamp * 1000)
        let lastWord = words[words.count - 1]
        let end = Int64((lastWord.timestamp + lastWord.duration) * 1000)

        return DiarizedSegment(
            id: UUID(),
            speakerIndex: speakerIndex,
            text: text,
            startOffsetMs: start,
            endOffsetMs: end
        )
    }

    private func buildSpeakerProfiles(
        speakerLabels: [Int],
        clusterLabels: [Int],
        embeddings: [SpeakerEmbedding]
    ) -> [SpeakerProfile] {
        speakerLabels.compactMap { label in
            // Collect all embeddings assigned to this speaker
            let speakerEmbeddings = zip(clusterLabels, embeddings)
                .filter { $0.0 == label }
                .map(\.1)

            let centroidEmbedding = SpeakerEmbedding.centroid(of: speakerEmbeddings)

            // Dummy legacy centroid for backward compatibility
            let dummyCentroid = SpeakerFeatureVector(
                meanPitch: 0, pitchStdDev: 0, meanEnergy: 0,
                meanSpectralCentroid: 0, meanJitter: 0, meanShimmer: 0
            )

            return SpeakerProfile(
                id: UUID(),
                speakerIndex: label,
                centroid: dummyCentroid,
                sampleCount: speakerEmbeddings.count,
                mfccEmbedding: centroidEmbedding
            )
        }
    }

    // MARK: - Single Speaker Fallback

    private func makeSingleSpeakerResult(
        wordSegments: [WordSegmentInfo],
        mfccResult: MelFilterbank.MFCCResult? = nil
    ) -> DiarizationResult {
        guard !wordSegments.isEmpty else {
            return DiarizationResult(segments: [], speakerCount: 0)
        }

        let text = wordSegments.map(\.substring).joined(separator: " ")
        let start = Int64(wordSegments[0].timestamp * 1000)
        let lastWord = wordSegments[wordSegments.count - 1]
        let end = Int64((lastWord.timestamp + lastWord.duration) * 1000)

        let segment = DiarizedSegment(
            id: UUID(),
            speakerIndex: 0,
            text: text,
            startOffsetMs: start,
            endOffsetMs: end
        )

        // Build single speaker profile with MFCC embedding if available
        var profiles: [SpeakerProfile] = []
        if let mfccResult = mfccResult, !mfccResult.mfccs.isEmpty {
            let embedding = SegmentEmbedder.computeEmbedding(
                mfccFrames: mfccResult.mfccs,
                deltas: mfccResult.deltas,
                deltaDeltas: mfccResult.deltaDeltas
            )
            let dummyCentroid = SpeakerFeatureVector(
                meanPitch: 0, pitchStdDev: 0, meanEnergy: 0,
                meanSpectralCentroid: 0, meanJitter: 0, meanShimmer: 0
            )
            profiles.append(SpeakerProfile(
                id: UUID(),
                speakerIndex: 0,
                centroid: dummyCentroid,
                sampleCount: 1,
                mfccEmbedding: embedding
            ))
        }

        return DiarizationResult(
            segments: [segment],
            speakerCount: 1,
            speakerProfiles: profiles
        )
    }
}
