import SwiftUI

/// Storage management screen showing disk usage, cleanup options,
/// backup/restore, and iCloud sync controls.
struct StorageManagementView: View {

    // MARK: - Environment

    @EnvironmentObject private var coordinator: RecordingCoordinator
    @StateObject private var viewModel: StorageManagementViewModel

    // MARK: - Init

    init(storageManager: StorageManager, cloudSyncManager: CloudSyncManager) {
        _viewModel = StateObject(
            wrappedValue: StorageManagementViewModel(
                storageManager: storageManager,
                cloudSyncManager: cloudSyncManager
            )
        )
    }

    // MARK: - Body

    var body: some View {
        Form {
            storageOverviewSection
            storageBreakdownSection
            deviceStorageSection
            sessionListSection
            cleanupSection
            backupSection
            iCloudSyncSection
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { RecordingIndicatorOverlay() }
        .onAppear {
            viewModel.loadStorage()
            viewModel.refreshiCloudStatus()
        }
        .alert(item: $viewModel.activeAlert) { alertType in
            alertFor(alertType)
        }
    }

    // MARK: - Storage Overview Section

    private var storageOverviewSection: some View {
        Section {
            if viewModel.isCalculating {
                HStack {
                    Spacer()
                    ProgressView("Calculating...")
                    Spacer()
                }
            } else {
                StorageBarChart(breakdown: viewModel.breakdown)
                    .frame(height: 32)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

                HStack {
                    Text("Total")
                        .font(.subheadline.bold())
                    Spacer()
                    Text(viewModel.formatBytes(viewModel.breakdown.totalBytes))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Storage Usage")
        }
    }

    // MARK: - Storage Breakdown Section

    private var storageBreakdownSection: some View {
        Section {
            StorageCategoryRow(
                color: .blue,
                icon: "waveform",
                title: "Audio Files",
                size: viewModel.breakdown.audioBytes,
                formatter: viewModel.formatBytes
            )
            StorageCategoryRow(
                color: .purple,
                icon: "cylinder",
                title: "Database",
                size: viewModel.breakdown.databaseBytes,
                formatter: viewModel.formatBytes
            )
            StorageCategoryRow(
                color: .orange,
                icon: "doc.text",
                title: "Exports",
                size: viewModel.breakdown.exportBytes,
                formatter: viewModel.formatBytes
            )
            StorageCategoryRow(
                color: .green,
                icon: "magnifyingglass",
                title: "Search Index",
                size: viewModel.breakdown.ftsIndexBytes,
                formatter: viewModel.formatBytes
            )
        } header: {
            Text("Breakdown")
        }
    }

    // MARK: - Device Storage Section

    private var deviceStorageSection: some View {
        Section {
            HStack {
                Label("Free Space", systemImage: "internaldrive")
                Spacer()
                Text(viewModel.formattedFreeSpace())
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Device")
        }
    }

    // MARK: - Session List Section

    private var sessionListSection: some View {
        Section {
            if viewModel.sessionStorageList.isEmpty {
                Text("No sessions recorded yet")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(viewModel.sessionStorageList.prefix(10)) { session in
                    sessionRow(session)
                }
                if viewModel.sessionStorageList.count > 10 {
                    Text("and \(viewModel.sessionStorageList.count - 10) more sessions...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Sessions by Audio Size")
        } footer: {
            if !viewModel.sessionStorageList.isEmpty {
                Text("Sorted by audio file size, largest first.")
            }
        }
    }

    private func sessionRow(_ session: StorageManager.SessionStorageInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title.isEmpty ? "Untitled Session" : session.title)
                    .font(.subheadline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(session.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(session.chunkCount) chunks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if session.hasAudio {
                Text(viewModel.formatBytes(session.audioSizeBytes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Label("No audio", systemImage: "speaker.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Cleanup Section

    private var cleanupSection: some View {
        Section {
            Picker("Older Than", selection: $viewModel.selectedCleanupPeriod) {
                ForEach(StorageManagementViewModel.CleanupPeriod.allCases) { period in
                    Text(period.displayText).tag(period)
                }
            }
            .pickerStyle(.menu)

            Button(role: .destructive) {
                viewModel.requestDeleteAudio()
            } label: {
                Label(
                    "Delete Audio Older Than \(viewModel.selectedCleanupPeriod.displayText)",
                    systemImage: "trash"
                )
            }

            Button(role: .destructive) {
                viewModel.requestDeleteExports()
            } label: {
                Label("Delete All Exports", systemImage: "doc.text.fill")
            }
            .disabled(viewModel.breakdown.exportBytes == 0)
        } header: {
            Text("Cleanup")
        } footer: {
            Text("Deleting audio keeps transcripts intact. This cannot be undone.")
        }
    }

    // MARK: - Backup Section

    private var backupSection: some View {
        Section {
            Button {
                viewModel.createBackup()
            } label: {
                HStack {
                    Label("Create Backup", systemImage: "arrow.down.doc")

                    Spacer()

                    if viewModel.isCreatingBackup {
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.isCreatingBackup)

            if viewModel.backups.isEmpty {
                Text("No backups yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.backups) { backup in
                    backupRow(backup)
                }
            }
        } header: {
            Text("Backups")
        } footer: {
            Text("Backups contain the database only, not audio files.")
        }
    }

    private func backupRow(_ backup: StorageManager.BackupInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(backup.name)
                    .font(.subheadline)
                    .lineLimit(1)

                Text(backup.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                + Text(" ")
                + Text(backup.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(viewModel.formatBytes(backup.sizeBytes))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                viewModel.requestDeleteBackup(at: backup.url)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    // MARK: - iCloud Sync Section

    private var iCloudSyncSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { viewModel.isSyncEnabled },
                set: { viewModel.toggleSync(enabled: $0) }
            )) {
                Label("iCloud Sync", systemImage: "icloud")
            }

            if viewModel.isSyncEnabled {
                HStack {
                    Text("Status")
                    Spacer()
                    syncStatusView
                }

                HStack {
                    Text("Last Sync")
                    Spacer()
                    Text(viewModel.lastSyncDisplayText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.iCloudStatusText.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text(viewModel.iCloudStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text("Syncs session metadata and transcripts across your devices. Audio files are not synced due to their large size.")
        }
    }

    @ViewBuilder
    private var syncStatusView: some View {
        switch viewModel.syncState {
        case .disabled:
            Text("Disabled")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .idle:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text("Up to date")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        case .syncing:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Syncing...")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
        case .error(let message):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Alerts

    private func alertFor(_ alertType: StorageManagementViewModel.AlertType) -> Alert {
        switch alertType {
        case .deleteAudioConfirmation:
            return Alert(
                title: Text("Delete Audio"),
                message: Text(
                    "This will permanently delete audio files for sessions older than "
                    + "\(viewModel.selectedCleanupPeriod.displayText). "
                    + "Transcripts will be preserved. This cannot be undone."
                ),
                primaryButton: .destructive(Text("Delete")) {
                    viewModel.confirmDeleteAudio()
                },
                secondaryButton: .cancel()
            )

        case .deleteExportsConfirmation:
            return Alert(
                title: Text("Delete All Exports"),
                message: Text("This will permanently delete all exported files. This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    viewModel.confirmDeleteExports()
                },
                secondaryButton: .cancel()
            )

        case .deleteBackupConfirmation(let url):
            return Alert(
                title: Text("Delete Backup"),
                message: Text("This will permanently delete the backup \"\(url.lastPathComponent)\". This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    viewModel.confirmDeleteBackup(at: url)
                },
                secondaryButton: .cancel()
            )

        case .backupSuccess(let url):
            return Alert(
                title: Text("Backup Created"),
                message: Text("Backup saved as \"\(url.lastPathComponent)\"."),
                dismissButton: .default(Text("OK"))
            )

        case .backupError(let message):
            return Alert(
                title: Text("Backup Failed"),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )

        case .cleanupResult(let count):
            let message = count > 0
                ? "Deleted audio for \(count) session(s)."
                : "No sessions found older than \(viewModel.selectedCleanupPeriod.displayText) with audio."
            return Alert(
                title: Text("Cleanup Complete"),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )

        case .iCloudUnavailable(let statusText):
            return Alert(
                title: Text("iCloud Unavailable"),
                message: Text(statusText),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

// MARK: - Storage Bar Chart

/// A horizontal stacked bar chart visualizing storage breakdown by category.
private struct StorageBarChart: View {

    let breakdown: StorageManager.StorageBreakdown

    var body: some View {
        GeometryReader { geometry in
            if breakdown.totalBytes == 0 {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 24)
                    .overlay {
                        Text("No data")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            } else {
                HStack(spacing: 1) {
                    barSegment(
                        color: .blue,
                        fraction: breakdown.audioFraction,
                        totalWidth: geometry.size.width
                    )
                    barSegment(
                        color: .purple,
                        fraction: breakdown.databaseFraction,
                        totalWidth: geometry.size.width
                    )
                    barSegment(
                        color: .orange,
                        fraction: breakdown.exportFraction,
                        totalWidth: geometry.size.width
                    )
                    barSegment(
                        color: .green,
                        fraction: breakdown.ftsFraction,
                        totalWidth: geometry.size.width
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(height: 24)
            }
        }
    }

    @ViewBuilder
    private func barSegment(color: Color, fraction: Double, totalWidth: CGFloat) -> some View {
        let width = max(fraction * totalWidth, fraction > 0 ? 4 : 0)
        if width > 0 {
            Rectangle()
                .fill(color)
                .frame(width: width)
        }
    }
}

// MARK: - Storage Category Row

/// A row showing a colored indicator, category name, and formatted size.
private struct StorageCategoryRow: View {

    let color: Color
    let icon: String
    let title: String
    let size: Int64
    let formatter: (Int64) -> String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Label(title, systemImage: icon)
                .font(.subheadline)

            Spacer()

            Text(formatter(size))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        Text("StorageManagementView requires dependencies")
    }
}
