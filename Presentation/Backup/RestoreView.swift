import SwiftUI
import UniformTypeIdentifiers

/// Restore view allowing users to select a .lifememobackup file and decrypt it.
struct RestoreView: View {

    @EnvironmentObject private var container: AppContainer
    @State private var showFilePicker = false
    @State private var selectedFileURL: URL?
    @State private var password = ""
    @State private var isRestoring = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            fileSelectionSection
            passwordSection
            restoreSection
        }
        .navigationTitle("Restore Backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                selectedFileURL = urls.first
            case .failure:
                errorMessage = "Could not access the selected file."
            }
        }
        .alert("Restore Complete", isPresented: $showSuccess) {
            Button("OK") {}
        } message: {
            Text("Your backup has been restored successfully.")
        }
        .alert("Restore Failed", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var fileSelectionSection: some View {
        Section {
            Button {
                showFilePicker = true
            } label: {
                HStack {
                    Label("Select Backup File", systemImage: "doc.badge.plus")
                    Spacer()
                    if let url = selectedFileURL {
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        } header: {
            Text("Backup File")
        } footer: {
            Text("Select a .lifememobackup file to restore.")
        }
    }

    private var passwordSection: some View {
        Section {
            SecureField("Backup Password", text: $password)
        } header: {
            Text("Password")
        } footer: {
            Text("Enter the password used when creating the backup.")
        }
    }

    private var restoreSection: some View {
        Section {
            Button {
                restoreBackup()
            } label: {
                HStack {
                    Text("Restore")
                    Spacer()
                    if isRestoring {
                        ProgressView()
                    }
                }
            }
            .disabled(selectedFileURL == nil || password.isEmpty || isRestoring)
        } footer: {
            Text("Existing sessions with the same ID will be skipped. Your current data will not be affected.")
        }
    }

    private func restoreBackup() {
        guard let url = selectedFileURL else { return }
        isRestoring = true
        Task {
            do {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                try await container.backupService.restoreFromEncryptedBackup(url: url, password: password)
                showSuccess = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isRestoring = false
        }
    }
}
