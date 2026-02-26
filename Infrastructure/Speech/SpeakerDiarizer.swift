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
    private static let canonicalSampleRate: Float = 16_000

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
            return makeSingleSpeakerResult(
                wordSegments: wordSegments,
                audioURL: audioURL
            )
        }
        let canonicalSamples = Self.resampleIfNeeded(
            samples: audio.samples,
            from: audio.sampleRate,
            to: Self.canonicalSampleRate
        )

        let mfccResult = MelFilterbank.extractMFCCs(
            samples: canonicalSamples,
            sampleRate: Self.canonicalSampleRate
        )
        let frameHopSec = Float(MelFilterbank.frameHop) / Self.canonicalSampleRate

        guard !mfccResult.mfccs.isEmpty else {
            return makeSingleSpeakerResult(
                wordSegments: wordSegments,
                audioURL: audioURL
            )
        }

        // Step 2: Voice Activity Detection
        let speechRegions = EnergyVAD.detectSpeechRegions(rmsEnergies: mfccResult.rmsEnergies)

        guard !speechRegions.isEmpty else {
            return makeSingleSpeakerResult(
                wordSegments: wordSegments,
                audioURL: audioURL
            )
        }

        // Step 3: BIC segmentation
        let boundaries = BICSegmenter.segment(
            mfccFrames: mfccResult.mfccs,
            speechRegions: speechRegions
        )

        // Build segment ranges from boundaries + speech regions
        let segmentRanges = buildSegmentRanges(
            speechRegions: speechRegions,
            boundaries: boundaries
        )

        guard segmentRanges.count > 1 else {
            return makeSingleSpeakerResult(
                wordSegments: wordSegments,
                mfccResult: mfccResult,
                audioURL: audioURL
            )
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
            return makeSingleSpeakerResult(
                wordSegments: wordSegments,
                mfccResult: mfccResult,
                audioURL: audioURL
            )
        }

        // Step 5: AHC clustering
        let clusterResult = AHCClusterer.cluster(embeddings: embeddings)

        guard clusterResult.numClusters > 1 else {
            return makeSingleSpeakerResult(
                wordSegments: wordSegments,
                mfccResult: mfccResult,
                audioURL: audioURL
            )
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
            segments: smoothed,
            frameHopSec: frameHopSec
        )

        // Build DiarizationResult
        return buildResult(
            mappedWords: mappedWords,
            segmentRanges: segmentRanges,
            clusterResult: clusterResult,
            embeddings: embeddings,
            audioURL: audioURL,
            frameHopSec: frameHopSec
        )
    }

    // MARK: - Segment Range Building

    private struct SegmentRange {
        let startFrame: Int
        let endFrame: Int
    }

    private func buildSegmentRanges(
        speechRegions: [EnergyVAD.SpeechRegion],
        boundaries: [BICSegmenter.Boundary]
    ) -> [SegmentRange] {
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
        segmentRanges: [SegmentRange],
        clusterResult: AHCClusterer.ClusterResult,
        embeddings: [SpeakerEmbedding],
        audioURL: URL,
        frameHopSec: Float
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
        let legacyCentroids = makeLegacyCentroids(
            audioURL: audioURL,
            segmentRanges: segmentRanges,
            clusterLabels: clusterResult.labels,
            frameHopSec: frameHopSec
        )

        // Build speaker profiles with MFCC embeddings
        let profiles = buildSpeakerProfiles(
            speakerLabels: Array(speakerIndices).sorted(),
            clusterLabels: clusterResult.labels,
            embeddings: embeddings,
            legacyCentroids: legacyCentroids
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
        embeddings: [SpeakerEmbedding],
        legacyCentroids: [Int: SpeakerFeatureVector]
    ) -> [SpeakerProfile] {
        speakerLabels.compactMap { label in
            // Collect all embeddings assigned to this speaker
            let speakerEmbeddings = zip(clusterLabels, embeddings)
                .filter { $0.0 == label }
                .map(\.1)

            let centroidEmbedding = SpeakerEmbedding.centroid(of: speakerEmbeddings)
            let centroid = legacyCentroids[label] ?? Self.zeroCentroid

            return SpeakerProfile(
                id: UUID(),
                speakerIndex: label,
                centroid: centroid,
                sampleCount: speakerEmbeddings.count,
                mfccEmbedding: centroidEmbedding
            )
        }
    }

    // MARK: - Single Speaker Fallback

    private func makeSingleSpeakerResult(
        wordSegments: [WordSegmentInfo],
        mfccResult: MelFilterbank.MFCCResult? = nil,
        audioURL: URL? = nil
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
            let centroid = audioURL.flatMap {
                estimateSingleSpeakerCentroid(
                    audioURL: $0,
                    wordSegments: wordSegments
                )
            } ?? Self.zeroCentroid
            profiles.append(SpeakerProfile(
                id: UUID(),
                speakerIndex: 0,
                centroid: centroid,
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

    private func makeLegacyCentroids(
        audioURL: URL,
        segmentRanges: [SegmentRange],
        clusterLabels: [Int],
        frameHopSec: Float
    ) -> [Int: SpeakerFeatureVector] {
        guard !segmentRanges.isEmpty else { return [:] }

        let windows: [(startSec: TimeInterval, durationSec: TimeInterval)] = segmentRanges.map { range in
            let startSec = TimeInterval(Double(range.startFrame) * Double(frameHopSec))
            let durationSec = TimeInterval(
                max(0.03, Double(range.endFrame - range.startFrame) * Double(frameHopSec))
            )
            return (startSec: startSec, durationSec: durationSec)
        }
        let features = AudioFeatureExtractor.extractFeatures(url: audioURL, windows: windows)

        var vectorsBySpeaker: [Int: [SpeakerFeatureVector]] = [:]
        for (idx, feature) in features.enumerated() {
            guard idx < clusterLabels.count else { continue }
            guard let vector = Self.makeFeatureVector(feature) else { continue }
            let label = clusterLabels[idx]
            vectorsBySpeaker[label, default: []].append(vector)
        }

        var centroids: [Int: SpeakerFeatureVector] = [:]
        for (label, vectors) in vectorsBySpeaker {
            if let centroid = SpeakerFeatureVector.centroid(of: vectors) {
                centroids[label] = centroid
            }
        }
        return centroids
    }

    private func estimateSingleSpeakerCentroid(
        audioURL: URL,
        wordSegments: [WordSegmentInfo]
    ) -> SpeakerFeatureVector? {
        guard let firstStart = wordSegments.min(by: { $0.timestamp < $1.timestamp })?.timestamp else {
            return nil
        }
        guard let lastEnd = wordSegments.max(
            by: { ($0.timestamp + $0.duration) < ($1.timestamp + $1.duration) }
        ).map({ $0.timestamp + $0.duration }) else {
            return nil
        }

        let durationSec = max(0.03, lastEnd - firstStart)
        let features = AudioFeatureExtractor.extractFeatures(
            url: audioURL,
            windows: [(startSec: firstStart, durationSec: durationSec)]
        )
        guard let first = features.first else { return nil }
        return Self.makeFeatureVector(first)
    }

    private static func makeFeatureVector(
        _ feature: AudioFeatureExtractor.WindowFeatures
    ) -> SpeakerFeatureVector? {
        guard let meanPitch = feature.meanPitch,
              let pitchStdDev = feature.pitchStdDev,
              let meanEnergy = feature.meanEnergy,
              let meanSpectralCentroid = feature.meanSpectralCentroid,
              let meanJitter = feature.jitter,
              let meanShimmer = feature.shimmer else {
            return nil
        }

        return SpeakerFeatureVector(
            meanPitch: meanPitch,
            pitchStdDev: pitchStdDev,
            meanEnergy: meanEnergy,
            meanSpectralCentroid: meanSpectralCentroid,
            meanJitter: meanJitter,
            meanShimmer: meanShimmer
        )
    }

    private static var zeroCentroid: SpeakerFeatureVector {
        SpeakerFeatureVector(
            meanPitch: 0,
            pitchStdDev: 0,
            meanEnergy: 0,
            meanSpectralCentroid: 0,
            meanJitter: 0,
            meanShimmer: 0
        )
    }

    private static func resampleIfNeeded(
        samples: [Float],
        from sourceRate: Float,
        to targetRate: Float
    ) -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard sourceRate > 0, targetRate > 0 else { return samples }
        guard abs(sourceRate - targetRate) > 1 else { return samples }
        guard samples.count > 1 else { return samples }

        let ratio = Double(sourceRate / targetRate)
        let outputCount = max(1, Int((Double(samples.count) / ratio).rounded()))
        var output = [Float](repeating: 0, count: outputCount)

        for i in 0..<outputCount {
            let srcPosition = Double(i) * ratio
            let left = Int(srcPosition)
            let right = min(left + 1, samples.count - 1)
            let fraction = Float(srcPosition - Double(left))
            let leftValue = samples[min(left, samples.count - 1)]
            let rightValue = samples[right]
            output[i] = leftValue + (rightValue - leftValue) * fraction
        }

        return output
    }
}
