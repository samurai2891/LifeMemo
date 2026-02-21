import Foundation
import Testing
@testable import LifeMemo

struct AudioLevelMonitorTests {
    private let sut = AudioLevelMonitor()

    @Test func emptyInputReturnsSilence() {
        let level = sut.calculateLevel(from: [], isSpeech: false)
        #expect(level == .silence)
    }

    @Test func silenceReturnsZeroLevel() {
        let silence = [Float](repeating: 0, count: 256)
        let level = sut.calculateLevel(from: silence, isSpeech: false)
        #expect(level.rms == 0)
        #expect(level.peak == 0)
        #expect(!level.isSpeech)
    }

    @Test func loudSignalHasHighLevel() {
        let loud = [Float](repeating: 0.8, count: 256)
        let level = sut.calculateLevel(from: loud, isSpeech: true)
        #expect(level.rms > 0.5)
        #expect(level.peak > 0.5)
        #expect(level.isSpeech)
    }

    @Test func speechFlagIsPassedThrough() {
        let samples = [Float](repeating: 0.1, count: 64)
        let withSpeech = sut.calculateLevel(from: samples, isSpeech: true)
        let withoutSpeech = sut.calculateLevel(from: samples, isSpeech: false)
        #expect(withSpeech.isSpeech)
        #expect(!withoutSpeech.isSpeech)
    }

    @Test func valuesClampedToOne() {
        // Samples > 1.0 (clipping input)
        let clipping = [Float](repeating: 1.5, count: 256)
        let level = sut.calculateLevel(from: clipping, isSpeech: false)
        #expect(level.rms <= 1.0)
        #expect(level.peak <= 1.0)
    }
}
