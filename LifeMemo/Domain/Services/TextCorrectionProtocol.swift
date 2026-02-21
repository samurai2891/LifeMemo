import Foundation

/// Record of a single correction applied by a pipeline stage.
struct CorrectionRecord: Sendable, Equatable {
    let original: String
    let replacement: String
    let stageName: String
    let confidence: Double
}

/// Output of a text correction operation.
struct CorrectionOutput: Sendable, Equatable {
    let originalText: String
    let correctedText: String
    let records: [CorrectionRecord]

    var wasModified: Bool { originalText != correctedText }
}

/// Full and lightweight correction for transcribed text.
protocol TextCorrectionProtocol: Sendable {
    /// Apply full correction pipeline to finalized text.
    func correct(_ text: String, locale: Locale) async -> CorrectionOutput
    /// Apply lightweight correction for live/partial results (stages 1, 2, 7 only).
    func correctLive(_ text: String, locale: Locale) async -> CorrectionOutput
}

/// A single stage in the correction pipeline.
protocol TextCorrectionStage: Sendable {
    var name: String { get }
    func apply(_ text: String) -> String
}
