import XCTest
import AVFAudio
@testable import LifeMemo

final class AudioConfigurationTests: XCTestCase {

    func testLowProfileUsesLowEncoderQuality() {
        let config = AudioConfiguration.low.toRecorderConfig()
        XCTAssertEqual(config.encoderQualityRawValue, AVAudioQuality.low.rawValue)
    }

    func testStandardProfileUsesMediumEncoderQuality() {
        let config = AudioConfiguration.standard.toRecorderConfig()
        XCTAssertEqual(config.encoderQualityRawValue, AVAudioQuality.medium.rawValue)
    }

    func testHighProfileUsesMaxEncoderQuality() {
        let config = AudioConfiguration.high.toRecorderConfig()
        XCTAssertEqual(config.encoderQualityRawValue, AVAudioQuality.max.rawValue)
    }
}
