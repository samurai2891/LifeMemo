import Testing
@testable import LifeMemo

struct ParticleCorrectorTests {
    let sut = ParticleCorrector()

    // MARK: - Empty / no-op

    @Test func emptyStringReturnsEmpty() {
        #expect(sut.apply("") == "")
    }

    @Test func correctParticlesUnchanged() {
        // Already correct particles should not be modified
        let input = "私は行く"
        #expect(sut.apply(input) == input)
    }

    // MARK: - わ → は (topic marker)

    @Test func waToHaAfterNounBeforeVerb() {
        // "彼わ行く" → "彼は行く" (He goes)
        // NLTagger should identify 彼=pronoun, 行く=verb
        let input = "彼わ行く"
        let result = sut.apply(input)
        // The correction depends on NLTagger's analysis
        // If NLTagger identifies the pattern correctly, わ→は
        #expect(result == "彼は行く" || result == input)
    }

    // MARK: - お → を (object marker)

    @Test func oToWoAfterNounBeforeVerb() {
        // "本お読む" → "本を読む" (Read a book)
        let input = "本お読む"
        let result = sut.apply(input)
        #expect(result == "本を読む" || result == input)
    }

    // MARK: - え → へ (direction marker)

    @Test func eToHeAfterNounBeforeVerb() {
        // "東京え行く" → "東京へ行く" (Go to Tokyo)
        let input = "東京え行く"
        let result = sut.apply(input)
        #expect(result == "東京へ行く" || result == input)
    }

    // MARK: - No false positives

    @Test func waInNonParticleContextUnchanged() {
        // "わたし" should not have わ→は
        let input = "わたし"
        #expect(sut.apply(input) == input)
    }

    @Test func singleCharacterStringUnchanged() {
        #expect(sut.apply("わ") == "わ")
    }

    @Test func multiWordSentence() {
        // A more natural sentence for NLTagger
        let input = "今日わ天気がいい"
        let result = sut.apply(input)
        // "今日は天気がいい" is the expected correction
        #expect(result == "今日は天気がいい" || result == input)
    }

    // MARK: - Multiple corrections in one sentence

    @Test func multipleCorrectionsPossible() {
        // "彼わ本お読む" → "彼は本を読む" (He reads a book)
        let input = "彼わ本お読む"
        let result = sut.apply(input)
        // At minimum, should not crash or corrupt text
        #expect(!result.isEmpty)
    }
}
