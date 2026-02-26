import AVFoundation
import Foundation

enum VoiceEnrollmentError: LocalizedError {
    case promptNotFound
    case invalidAudioFile
    case insufficientSpeech
    case lowQuality([String])
    case embeddingUnavailable
    case insufficientAcceptedSamples

    var errorDescription: String? {
        switch self {
        case .promptNotFound:
            return "選択した登録プロンプトが見つかりません。"
        case .invalidAudioFile:
            return "録音ファイルの読み込みに失敗しました。"
        case .insufficientSpeech:
            return "音声区間が短すぎます。もう一度録音してください。"
        case .lowQuality(let reasons):
            return "録音品質が基準を満たしません: \(reasons.joined(separator: " / "))"
        case .embeddingUnavailable:
            return "音声特徴の抽出に失敗しました。静かな場所で再試行してください。"
        case .insufficientAcceptedSamples:
            return "すべての登録文を録音してから完了してください。"
        }
    }
}

/// Builds and persists a single-user ("Me") voice enrollment profile.
actor VoiceEnrollmentService {

    private struct EnrollmentTake {
        let promptId: Int
        let embedding: SpeakerEmbedding
        let centroid: SpeakerFeatureVector
        let quality: EnrollmentSampleQuality
    }

    private let repository: VoiceEnrollmentProfileStoring
    private var pendingTakes: [Int: EnrollmentTake] = [:]

    init(repository: VoiceEnrollmentProfileStoring) {
        self.repository = repository
    }

    func prompts() -> [VoiceEnrollmentPrompt] {
        VoiceEnrollmentPrompt.defaultPrompts
    }

    func startEnrollmentSession() {
        pendingTakes.removeAll()
    }

    func activeProfile() -> VoiceEnrollmentProfile? {
        repository.activeProfile()
    }

    func registerTake(promptId: Int, audioURL: URL) throws -> EnrollmentSampleQuality {
        guard VoiceEnrollmentPrompt.defaultPrompts.contains(where: { $0.id == promptId }) else {
            throw VoiceEnrollmentError.promptNotFound
        }

        let analysis = try analyzeTake(url: audioURL)
        if !analysis.quality.accepted {
            throw VoiceEnrollmentError.lowQuality(analysis.quality.rejectionReasons)
        }

        let take = EnrollmentTake(
            promptId: promptId,
            embedding: analysis.embedding,
            centroid: analysis.centroid,
            quality: analysis.quality
        )
        pendingTakes[promptId] = take
        return analysis.quality
    }

    func pendingPromptIds() -> Set<Int> {
        Set(pendingTakes.keys)
    }

    func finalizeEnrollment(displayName: String = "Me") throws -> VoiceEnrollmentProfile {
        let prompts = VoiceEnrollmentPrompt.defaultPrompts
        guard pendingTakes.count == prompts.count else {
            throw VoiceEnrollmentError.insufficientAcceptedSamples
        }

        let takes = prompts.compactMap { pendingTakes[$0.id] }
        guard !takes.isEmpty else {
            throw VoiceEnrollmentError.insufficientAcceptedSamples
        }

        let filteredEmbeddings = filterOutlierEmbeddings(takes.map(\.embedding))
        guard let referenceEmbedding = SpeakerEmbedding.centroid(of: filteredEmbeddings) else {
            throw VoiceEnrollmentError.embeddingUnavailable
        }

        guard let referenceCentroid = SpeakerFeatureVector.centroid(of: takes.map(\.centroid)) else {
            throw VoiceEnrollmentError.embeddingUnavailable
        }

        let qualityStats = VoiceEnrollmentQualityStats(
            acceptedSamples: takes.count,
            averageSnrDb: takes.map(\.quality.snrDb).reduce(0, +) / Float(max(1, takes.count)),
            averageSpeechRatio: takes.map(\.quality.speechRatio).reduce(0, +) / Float(max(1, takes.count)),
            averageClippingRatio: takes.map(\.quality.clippingRatio).reduce(0, +) / Float(max(1, takes.count))
        )

        let nextVersion = max(1, (repository.activeProfile()?.version ?? 0) + 1)
        let profile = VoiceEnrollmentProfile(
            id: UUID(),
            displayName: displayName,
            referenceEmbedding: referenceEmbedding,
            referenceCentroid: referenceCentroid,
            version: nextVersion,
            isActive: true,
            qualityStats: qualityStats,
            adaptationCount: 0,
            updatedAt: Date()
        )

        repository.saveActiveProfile(profile)
        pendingTakes.removeAll()
        return profile
    }

    func clearEnrollment() {
        pendingTakes.removeAll()
        repository.deactivateProfile()
    }

    private struct TakeAnalysis {
        let quality: EnrollmentSampleQuality
        let embedding: SpeakerEmbedding
        let centroid: SpeakerFeatureVector
    }

    private func analyzeTake(url: URL) throws -> TakeAnalysis {
        guard let audio = MelFilterbank.readSamples(url: url) else {
            throw VoiceEnrollmentError.invalidAudioFile
        }

        let samples = audio.samples
        let sampleRate = audio.sampleRate
        guard !samples.isEmpty else { throw VoiceEnrollmentError.invalidAudioFile }

        let canonicalRate: Float = 16_000
        let canonicalSamples = Self.resampleIfNeeded(samples: samples, from: sampleRate, to: canonicalRate)
        guard !canonicalSamples.isEmpty else { throw VoiceEnrollmentError.invalidAudioFile }

        let mfcc = MelFilterbank.extractMFCCs(samples: canonicalSamples, sampleRate: canonicalRate)
        guard !mfcc.mfccs.isEmpty else { throw VoiceEnrollmentError.insufficientSpeech }

        let speechRegions = EnergyVAD.detectSpeechRegions(rmsEnergies: mfcc.rmsEnergies)
        let speechMask = Self.buildSpeechMask(totalFrames: mfcc.rmsEnergies.count, regions: speechRegions)
        let speechFrameCount = speechMask.filter { $0 }.count
        guard speechFrameCount >= 12 else { throw VoiceEnrollmentError.insufficientSpeech }

        let speechRatio = Float(speechFrameCount) / Float(max(1, speechMask.count))
        let speechEnergies = zip(mfcc.rmsEnergies, speechMask).compactMap { $1 ? $0 : nil }
        let noiseEnergies = zip(mfcc.rmsEnergies, speechMask).compactMap { !$1 ? $0 : nil }
        let speechMean = speechEnergies.reduce(0, +) / Float(max(1, speechEnergies.count))
        let noiseMean = noiseEnergies.reduce(0, +) / Float(max(1, noiseEnergies.count))
        let snrDb = 20 * log10f(max(speechMean, 1e-6) / max(noiseMean, 1e-6))
        let clippingRatio = Float(samples.filter { abs($0) >= 0.98 }.count) / Float(max(1, samples.count))
        let durationSec = Double(samples.count) / Double(max(1, Int(sampleRate)))

        var reasons: [String] = []
        if durationSec < 4.5 { reasons.append("duration_short") }
        if durationSec > 15.0 { reasons.append("duration_long") }
        if snrDb < 8.0 { reasons.append("snr_low") }
        if speechRatio < 0.45 { reasons.append("speech_ratio_low") }
        if speechRatio > 0.98 { reasons.append("speech_ratio_high") }
        if clippingRatio > 0.02 { reasons.append("clipping_high") }
        let accepted = reasons.isEmpty

        guard accepted else {
            throw VoiceEnrollmentError.lowQuality(reasons)
        }

        guard let embedding = SegmentEmbedder.computeEmbedding(
            mfccFrames: mfcc.mfccs,
            deltas: mfcc.deltas,
            deltaDeltas: mfcc.deltaDeltas
        ) else {
            throw VoiceEnrollmentError.embeddingUnavailable
        }

        let windows: [(startSec: TimeInterval, durationSec: TimeInterval)] = [
            (startSec: 0, durationSec: durationSec)
        ]
        let features = AudioFeatureExtractor.extractFeatures(url: url, windows: windows)
        guard let feature = features.first,
              let centroid = Self.makeFeatureVector(feature) else {
            throw VoiceEnrollmentError.embeddingUnavailable
        }

        let quality = EnrollmentSampleQuality(
            snrDb: snrDb,
            speechRatio: speechRatio,
            clippingRatio: clippingRatio,
            durationSec: durationSec,
            accepted: true,
            rejectionReasons: []
        )
        return TakeAnalysis(quality: quality, embedding: embedding, centroid: centroid)
    }

    private func filterOutlierEmbeddings(_ embeddings: [SpeakerEmbedding]) -> [SpeakerEmbedding] {
        guard embeddings.count >= 6,
              let center = SpeakerEmbedding.centroid(of: embeddings) else {
            return embeddings
        }

        let scored = embeddings.enumerated().map { idx, emb in
            (idx, emb.cosineDistance(to: center))
        }.sorted { $0.1 > $1.1 }

        let removeCount = max(1, Int(Float(embeddings.count) * 0.10))
        let removeIndexes = Set(scored.prefix(removeCount).map(\.0))
        let filtered = embeddings.enumerated()
            .filter { !removeIndexes.contains($0.offset) }
            .map(\.element)

        return filtered.isEmpty ? embeddings : filtered
    }

    private static func buildSpeechMask(
        totalFrames: Int,
        regions: [EnergyVAD.SpeechRegion]
    ) -> [Bool] {
        guard totalFrames > 0 else { return [] }
        var mask = [Bool](repeating: false, count: totalFrames)
        for region in regions {
            let start = max(0, min(totalFrames - 1, region.startFrame))
            let end = max(start, min(totalFrames, region.endFrame))
            guard start < end else { continue }
            for idx in start..<end {
                mask[idx] = true
            }
        }
        return mask
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
