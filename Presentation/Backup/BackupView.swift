import SwiftUI

/// Backup creation view with session selection, audio inclusion toggle,
/// password input, and progress display.
struct BackupView: View {

    @EnvironmentObject private var container: AppContainer
    @State private var selectedSessionIds: Set<UUID> = []
    @State private var includeAudio = true
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isCreating = false
    @State private var showResult = false
    @State private var resultURL: URL?
    @State private var errorMessage: String?
    @State private var showShareSheet = false

    private var sessions: [SessionSummary] {
        container.repository.fetchAllSessions().map { $0.toSummary() }
    }

    var body: some View {
        Form {
            sessionSelectionSection
            optionsSection
            passwordSection
            createSection
        }
        .navigationTitle("Create Backup")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Backup Created", isPresented: .constant(resultURL != nil)) {
            Button("Share") {
                showShareSheet = true
                resultURL = nil
            }
            Button("OK") { resultURL = nil }
        } message: {
            Text("Your encrypted backup has been created successfully.")
        }
        .alert("Backup Failed", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = resultURL {
                ShareSheetWrapper(activityItems: [url])
            }
        }
    }

    private var sessionSelectionSection: some View {
        Section {
            Button(selectedSessionIds.count == sessions.count ? "Deselect All" : "Select All") {
                if selectedSessionIds.count == sessions.count {
                    selectedSessionIds.removeAll()
                } else {
                    selectedSessionIds = Set(sessions.map(\.id))
                }
            }

            ForEach(sessions) { session in
                HStack {
                    Image(systemName: selectedSessionIds.contains(session.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedSessionIds.contains(session.id) ? Color.accentColor : .secondary)

                    VStack(alignment: .leading) {
                        Text(session.title.isEmpty ? "Untitled" : session.title)
                            .font(.subheadline)
                        Text(session.startedAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedSessionIds.contains(session.id) {
                        selectedSessionIds.remove(session.id)
                    } else {
                        selectedSessionIds.insert(session.id)
                    }
                }
            }
        } header: {
            Text("Sessions (\(selectedSessionIds.count) selected)")
        }
    }

    private var optionsSection: some View {
        Section {
            Toggle("Include Audio Files", isOn: $includeAudio)
        } header: {
            Text("Options")
        } footer: {
            Text("Audio files significantly increase backup size. Transcripts are always included.")
        }
    }

    private var passwordSection: some View {
        Section {
            SecureField("Password", text: $password)
            SecureField("Confirm Password", text: $confirmPassword)
        } header: {
            Text("Encryption Password")
        } footer: {
            Text("You will need this password to restore the backup. It cannot be recovered.")
        }
    }

    private var createSection: some View {
        Section {
            Button {
                createBackup()
            } label: {
                HStack {
                    Text("Create Encrypted Backup")
                    Spacer()
                    if isCreating {
                        ProgressView()
                    }
                }
            }
            .disabled(!canCreate)
        }
    }

    private var canCreate: Bool {
        !selectedSessionIds.isEmpty
            && !password.isEmpty
            && password == confirmPassword
            && password.count >= 8
            && !isCreating
    }

    private func createBackup() {
        isCreating = true
        Task {
            do {
                let url = try await container.backupService.createEncryptedBackup(
                    sessionIds: Array(selectedSessionIds),
                    includeAudio: includeAudio,
                    password: password
                )
                resultURL = url
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }
}

private struct ShareSheetWrapper: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
