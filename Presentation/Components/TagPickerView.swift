import SwiftUI

/// A sheet view for managing tags assigned to a session.
///
/// Displays all existing tags with checkmarks for currently assigned ones.
/// Tapping a tag toggles its assignment. A text field at the bottom allows
/// creating new tags on the fly.
struct TagPickerView: View {

    // MARK: - Properties

    let sessionId: UUID
    let repository: SessionRepository

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var allTags: [TagInfo] = []
    @State private var sessionTagIds: Set<UUID>
    @State private var newTagName: String = ""
    @State private var errorMessage: String?

    // MARK: - Init

    init(sessionId: UUID, repository: SessionRepository, sessionTags: [TagInfo]) {
        self.sessionId = sessionId
        self.repository = repository
        _sessionTagIds = State(initialValue: Set(sessionTags.map(\.id)))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                existingTagsSection
                createTagSection
            }
            .navigationTitle("Tags")
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
            .onAppear { loadAllTags() }
        }
    }

    // MARK: - Existing Tags Section

    private var existingTagsSection: some View {
        Section("Existing Tags") {
            if allTags.isEmpty {
                Text("No tags yet. Create one below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(allTags) { tag in
                    tagRow(tag)
                }
            }
        }
    }

    private func tagRow(_ tag: TagInfo) -> some View {
        Button {
            toggleTag(tag)
        } label: {
            HStack {
                TagChipView(tag: tag)

                Spacer()

                if sessionTagIds.contains(tag.id) {
                    Image(systemName: "checkmark")
                        .font(.body.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Create Tag Section

    private var createTagSection: some View {
        Section("Create New Tag") {
            HStack(spacing: 8) {
                TextField("Tag name", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { createAndAssignTag() }

                Button {
                    createAndAssignTag()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Actions

    private func loadAllTags() {
        allTags = repository.fetchAllTags().map { $0.toInfo() }
    }

    private func toggleTag(_ tag: TagInfo) {
        if sessionTagIds.contains(tag.id) {
            repository.removeTag(tagId: tag.id, fromSession: sessionId)
            sessionTagIds.remove(tag.id)
        } else {
            repository.addTag(tagId: tag.id, toSession: sessionId)
            sessionTagIds.insert(tag.id)
        }
    }

    private func createAndAssignTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let tagId = repository.createTag(name: trimmed)
        repository.addTag(tagId: tagId, toSession: sessionId)

        sessionTagIds.insert(tagId)
        newTagName = ""
        loadAllTags()
    }
}

#Preview {
    TagPickerView(
        sessionId: UUID(),
        repository: SessionRepository(
            context: CoreDataStack(modelName: "LifeMemo").viewContext,
            fileStore: FileStore()
        ),
        sessionTags: []
    )
}
