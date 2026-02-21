import Testing
@testable import LifeMemo

struct TextNormalizerTests {
    let sut = TextNormalizer()

    // MARK: - Empty / no-op

    @Test func emptyStringReturnsEmpty() {
        #expect(sut.apply("") == "")
    }

    @Test func pureJapaneseUnchanged() {
        let input = "東京都渋谷区"
        #expect(sut.apply(input) == input)
    }

    // MARK: - Full-width ASCII → half-width

    @Test func fullWidthLettersConvertedToHalfWidth() {
        // Ａ = U+FF21, ｚ = U+FF5A
        #expect(sut.apply("Ａ") == "A")
        #expect(sut.apply("ａｂｃ") == "abc")
        #expect(sut.apply("Ｈｅｌｌｏ") == "Hello")
    }

    @Test func fullWidthDigitsConvertedToHalfWidth() {
        #expect(sut.apply("１２３") == "123")
        #expect(sut.apply("２０２６年") == "2026年")
    }

    @Test func fullWidthSymbolsConvertedToHalfWidth() {
        #expect(sut.apply("＋") == "+")
        #expect(sut.apply("＝") == "=")
    }

    @Test func ideographicSpaceConvertedToASCIISpace() {
        // U+3000 → U+0020
        #expect(sut.apply("東京\u{3000}都") == "東京 都")
    }

    @Test func fullWidthKatakanaPreserved() {
        // Katakana should NOT be converted to half-width
        let input = "カタカナ"
        #expect(sut.apply(input) == input)
    }

    // MARK: - Whitespace normalization

    @Test func multipleSpacesCollapsed() {
        #expect(sut.apply("東京   都") == "東京 都")
    }

    @Test func tabsCollapsedToSpace() {
        #expect(sut.apply("東京\t\t都") == "東京 都")
    }

    @Test func leadingTrailingWhitespaceTrimmed() {
        #expect(sut.apply("  東京都  ") == "東京都")
    }

    @Test func newlinesPreserved() {
        #expect(sut.apply("一行目\n二行目") == "一行目\n二行目")
    }

    // MARK: - Mixed scenarios

    @Test func mixedFullWidthAndWhitespace() {
        let input = "Ｈｅｌｌｏ　　Ｗｏｒｌｄ"
        #expect(sut.apply(input) == "Hello World")
    }
}
