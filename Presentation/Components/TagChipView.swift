import SwiftUI

/// A compact capsule-shaped chip displaying a tag name with an optional remove button.
///
/// Use this view wherever tags are displayed inline (session headers, search results, etc.).
/// When `onRemove` is provided, a small "X" button appears on the trailing edge.
struct TagChipView: View {

    // MARK: - Properties

    let tag: TagInfo
    var onRemove: (() -> Void)? = nil

    // MARK: - Body

    var body: some View {
        HStack(spacing: 4) {
            Text(tag.name)
                .font(.caption)
                .lineLimit(1)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(.white)
        .background(chipColor)
        .clipShape(Capsule())
    }

    // MARK: - Helpers

    private var chipColor: Color {
        guard let hex = tag.colorHex else {
            return Color.accentColor
        }
        return Color(hex: hex) ?? Color.accentColor
    }
}

// MARK: - Color+Hex

extension Color {

    /// Creates a `Color` from a hex string (e.g. "#FF5733" or "FF5733").
    /// Returns `nil` if the string cannot be parsed.
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16) else {
            return nil
        }

        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    HStack {
        TagChipView(tag: TagInfo(id: UUID(), name: "Work", colorHex: "#FF5733"))
        TagChipView(tag: TagInfo(id: UUID(), name: "Personal", colorHex: nil))
        TagChipView(
            tag: TagInfo(id: UUID(), name: "Removable", colorHex: "#3366FF"),
            onRemove: {}
        )
    }
    .padding()
}
