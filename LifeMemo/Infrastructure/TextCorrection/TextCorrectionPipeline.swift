import Foundation

/// Orchestrator that composes all 7 correction stages into a sequential pipeline.
///
/// Full pipeline (for finalized transcription results):
///   1. TextNormalizer — Full-width/half-width, whitespace
///   2. PunctuationCorrector — Japanese punctuation repair
///   3. ParticleCorrector — は/わ, を/お, へ/え (NLTagger POS)
///   4. CompoundWordJoiner — Re-join split compound words
///   5. KanjiDisambiguator — N-gram + NLEmbedding kanji selection
///   6. CounterWordFixer — Counter words + archaic numeral normalization
///   7. AdaptiveDictionary — User-learned corrections
///
/// Live pipeline (~5ms, for partial speech results):
///   Stages 1, 2, 7 only.
struct TextCorrectionPipeline: TextCorrectionProtocol {

    private let fullStages: [TextCorrectionStage]
    private let liveStages: [TextCorrectionStage]

    init(adaptiveDictionary: AdaptiveDictionary = AdaptiveDictionary()) {
        let normalizer = TextNormalizer()
        let punctuation = PunctuationCorrector()
        let particle = ParticleCorrector()
        let compoundJoiner = CompoundWordJoiner()
        let kanjiDisambiguator = KanjiDisambiguator()
        let counterFixer = CounterWordFixer()

        fullStages = [
            normalizer,            // Stage 1
            punctuation,           // Stage 2
            particle,              // Stage 3
            compoundJoiner,        // Stage 4
            kanjiDisambiguator,    // Stage 5
            counterFixer,          // Stage 6
            adaptiveDictionary,    // Stage 7
        ]

        // Live mode: lightweight stages only (~5ms budget)
        liveStages = [
            normalizer,            // Stage 1
            punctuation,           // Stage 2
            adaptiveDictionary,    // Stage 7
        ]
    }

    // MARK: - TextCorrectionProtocol

    func correct(_ text: String, locale: Locale) async -> CorrectionOutput {
        guard isJapaneseLocale(locale) else {
            return CorrectionOutput(
                originalText: text, correctedText: text, records: []
            )
        }
        return applyStages(fullStages, to: text)
    }

    func correctLive(_ text: String, locale: Locale) async -> CorrectionOutput {
        guard isJapaneseLocale(locale) else {
            return CorrectionOutput(
                originalText: text, correctedText: text, records: []
            )
        }
        return applyStages(liveStages, to: text)
    }

    // MARK: - Internal

    private func applyStages(
        _ stages: [TextCorrectionStage], to text: String
    ) -> CorrectionOutput {
        var current = text
        var records: [CorrectionRecord] = []

        for stage in stages {
            let before = current
            current = stage.apply(current)
            if current != before {
                records.append(CorrectionRecord(
                    original: before,
                    replacement: current,
                    stageName: stage.name,
                    confidence: 1.0
                ))
            }
        }

        return CorrectionOutput(
            originalText: text,
            correctedText: current,
            records: records
        )
    }

    private func isJapaneseLocale(_ locale: Locale) -> Bool {
        locale.language.languageCode?.identifier == "ja"
    }
}
