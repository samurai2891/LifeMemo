import SwiftUI

/// Sheet for editing speaker names assigned during diarization.
///
/// Displays each detected speaker with their color indicator and allows
/// the user to provide custom names (e.g. "Taro", "Hanako") that will
/// replace the default "Speaker 1", "Speaker 2" labels.
struct SpeakerManagementSheet: View {

    @ObservedObject var viewModel: SessionDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var editedNames: [Int: String] = [:]

    var body: some View {
        NavigationStack {
            List {
                ForEach(0..<viewModel.speakerCount, id: \.self) { index in
                    speakerRow(index: index)
                }
            }
            .navigationTitle("Speakers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                }
            }
            .onAppear {
                editedNames = viewModel.speakerNames
            }
        }
    }

    // MARK: - Row

    private func speakerRow(index: Int) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(SpeakerColors.color(for: index))
                .frame(width: 12, height: 12)

            TextField(
                SpeakerColors.defaultName(for: index),
                text: Binding(
                    get: { editedNames[index] ?? "" },
                    set: { editedNames[index] = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Save

    private func saveChanges() {
        for (index, name) in editedNames {
            viewModel.renameSpeaker(index: index, newName: name)
        }
    }
}
