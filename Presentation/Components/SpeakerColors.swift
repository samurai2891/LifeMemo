import SwiftUI

/// Color palette and display name helpers for speaker labels.
enum SpeakerColors {

    static let palette: [Color] = [
        .blue, .green, .orange, .purple,
        .pink, .teal, .indigo, .mint
    ]

    /// Returns the color for a given speaker index, cycling through the palette.
    static func color(for index: Int) -> Color {
        guard index >= 0 else { return .secondary }
        return palette[index % palette.count]
    }

    /// Returns a default display name such as "Speaker 1", "Speaker 2", etc.
    static func defaultName(for index: Int) -> String {
        "Speaker \(index + 1)"
    }
}
