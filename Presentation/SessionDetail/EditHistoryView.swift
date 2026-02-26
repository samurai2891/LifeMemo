import SwiftUI

/// Sheet view displaying the edit timeline for a single transcript segment.
///
/// Shows chronological edit entries with diffs, relative timestamps,
/// and revert actions. Includes an "Original" section at the top and
/// "Current" section at the bottom.
struct EditHistoryView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: SessionDetailViewModel
    let segmentText: String
    let originalText: String?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.selectedSegmentHistory.isEmpty {
                    emptyState
                } else {
                    historyList
                }
            }
            .navigationTitle("Edit History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        viewModel.dismissEditHistory()
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Edit History",
            systemImage: "clock.arrow.circlepath",
            description: Text("No edit history available for this segment.")
        )
    }

    // MARK: - History List

    private var historyList: some View {
        List {
            // Original text section
            if let original = originalText {
                originalSection(original)
            }

            // Edit entries section
            editsSection

            // Current text section
            currentSection
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Original Section

    private func originalSection(_ original: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Original")
                        .font(.subheadline.bold())
                } icon: {
                    Image(systemName: "text.badge.star")
                        .foregroundStyle(.blue)
                }

                Text(original)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineSpacing(3)

                if let segmentId = viewModel.showingHistoryForSegmentId {
                    Button(role: .destructive) {
                        viewModel.revertToOriginal(segmentId: segmentId)
                    } label: {
                        Label("Revert to original", systemImage: "arrow.uturn.backward")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Original Text")
        }
    }

    // MARK: - Edits Section

    private var editsSection: some View {
        Section {
            ForEach(viewModel.selectedSegmentHistory) { entry in
                editEntryRow(entry)
            }
        } header: {
            Text("Edits")
        }
    }

    private func editEntryRow(_ entry: EditHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: edit badge + relative timestamp
            HStack(spacing: 8) {
                editBadge(index: entry.editIndex)

                Text(relativeTimestamp(entry.editedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            // Previous text (struck through)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "minus.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.7))
                    .padding(.top, 2)

                Text(entry.previousText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .strikethrough(true, color: .red.opacity(0.5))
                    .lineSpacing(2)
            }

            // Arrow separator
            Image(systemName: "arrow.down")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)

            // New text
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green.opacity(0.7))
                    .padding(.top, 2)

                Text(entry.newText)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
            }

            // Revert button
            Button(role: .destructive) {
                viewModel.revertToVersion(historyEntryId: entry.id)
            } label: {
                Label("Revert to this version", systemImage: "arrow.uturn.backward")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Current Section

    private var currentSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Current")
                        .font(.subheadline.bold())
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Text(segmentText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineSpacing(3)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Current Text")
        }
    }

    // MARK: - Helpers

    private func editBadge(index: Int) -> some View {
        Text("Edit #\(index)")
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }

    private func relativeTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#if DEBUG
private struct EditHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        Text("EditHistoryView requires SessionDetailViewModel")
    }
}
#endif
