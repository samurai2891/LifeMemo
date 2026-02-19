import SwiftUI

/// A row displaying a confirmed live transcription segment.
///
/// Supports two modes:
/// - **Display**: Shows segment text with an edit button and optional "edited" badge.
/// - **Editing**: Shows a TextEditor with Cancel/Save buttons for inline editing.
struct LiveSegmentRow: View {

    let segment: LiveSegment
    let isEditing: Bool
    @Binding var editText: String
    let isEdited: Bool
    let onTapEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        if isEditing {
            editingView
        } else {
            displayView
        }
    }

    // MARK: - Display Mode

    private var displayView: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(segment.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Button(action: onTapEdit) {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(Circle())
                }

                if isEdited {
                    Text(NSLocalizedString("edited", comment: ""))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Editing Mode

    private var editingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $editText)
                .font(.subheadline)
                .frame(minHeight: 60, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 1)
                )

            HStack {
                Spacer()

                Button(NSLocalizedString("Cancel", comment: ""), action: onCancel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(NSLocalizedString("Save", comment: ""), action: onSave)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
