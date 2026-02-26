import SwiftUI

/// A sheet view for selecting or creating a folder for a session.
///
/// Displays all existing folders with a checkmark on the currently assigned one,
/// a "None" option to remove folder assignment, and a text field for creating
/// new folders on the fly.
struct FolderPickerView: View {

    // MARK: - Properties

    let sessionId: UUID
    let repository: SessionRepository

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var folders: [FolderInfo] = []
    @State private var selectedFolderId: UUID?
    @State private var newFolderName: String = ""
    @State private var errorMessage: String?

    // MARK: - Init

    init(sessionId: UUID, currentFolderId: UUID?, repository: SessionRepository) {
        self.sessionId = sessionId
        self.repository = repository
        _selectedFolderId = State(initialValue: currentFolderId)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                folderSelectionSection
                createFolderSection
            }
            .navigationTitle("Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear { loadFolders() }
        }
    }

    // MARK: - Folder Selection Section

    private var folderSelectionSection: some View {
        Section("Select Folder") {
            // "None" option to remove folder assignment
            Button {
                selectFolder(nil)
            } label: {
                HStack {
                    Label("None", systemImage: "folder.badge.minus")
                        .foregroundStyle(.primary)

                    Spacer()

                    if selectedFolderId == nil {
                        Image(systemName: "checkmark")
                            .font(.body.bold())
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Existing folders
            ForEach(folders) { folder in
                Button {
                    selectFolder(folder.id)
                } label: {
                    HStack {
                        Label(folder.name, systemImage: "folder.fill")
                            .foregroundStyle(.primary)

                        Spacer()

                        if selectedFolderId == folder.id {
                            Image(systemName: "checkmark")
                                .font(.body.bold())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Create Folder Section

    private var createFolderSection: some View {
        Section("Create New Folder") {
            HStack(spacing: 8) {
                TextField("Folder name", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { createAndSelectFolder() }

                Button {
                    createAndSelectFolder()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Actions

    private func loadFolders() {
        folders = repository.fetchAllFolders().map { $0.toInfo() }
    }

    private func selectFolder(_ folderId: UUID?) {
        repository.setSessionFolder(sessionId: sessionId, folderId: folderId)
        selectedFolderId = folderId
    }

    private func createAndSelectFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let folderId = repository.createFolder(name: trimmed)
        repository.setSessionFolder(sessionId: sessionId, folderId: folderId)

        selectedFolderId = folderId
        newFolderName = ""
        loadFolders()
    }
}

#if DEBUG
private struct FolderPickerView_Previews: PreviewProvider {
    static var previews: some View {
        FolderPickerView(
            sessionId: UUID(),
            currentFolderId: nil,
            repository: SessionRepository(
                context: CoreDataStack(modelName: "LifeMemo").viewContext,
                fileStore: FileStore()
            )
        )
    }
}
#endif
