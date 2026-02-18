import SwiftUI

/// Guided cleanup view showing storage breakdown and recommended actions.
///
/// Provides a clear visual of what's using space and offers one-tap
/// cleanup actions with confirmation dialogs.
struct StorageCleanupGuideView: View {

    @EnvironmentObject private var container: AppContainer
    @State private var showDeleteOldAudio = false
    @State private var showDeleteExports = false
    @State private var deletedCount = 0
    @State private var showResult = false

    var body: some View {
        Form {
            usageOverviewSection
            recommendationsSection
            actionsSection
        }
        .navigationTitle("Cleanup Guide")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Cleanup Complete", isPresented: $showResult) {
            Button("OK") {}
        } message: {
            Text(deletedCount > 0
                ? "Removed audio from \(deletedCount) session(s). Transcripts preserved."
                : "No old audio files found to clean up."
            )
        }
        .confirmationDialog(
            "Delete Old Audio",
            isPresented: $showDeleteOldAudio,
            titleVisibility: .visible
        ) {
            Button("Delete Audio Older Than 30 Days", role: .destructive) {
                deletedCount = container.storageManager.deleteAudioOlderThan(days: 30)
                showResult = true
            }
            Button("Delete Audio Older Than 7 Days", role: .destructive) {
                deletedCount = container.storageManager.deleteAudioOlderThan(days: 7)
                showResult = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete All Exports",
            isPresented: $showDeleteExports,
            titleVisibility: .visible
        ) {
            Button("Delete All Exports", role: .destructive) {
                container.storageManager.deleteAllExports()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var usageOverviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                let manager = container.storageLimitManager

                HStack {
                    Text("Usage")
                    Spacer()
                    Text(String(format: "%.1f GB / %.0f GB", manager.currentUsageGB, manager.limitGB))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: min(manager.usagePercentage, 100), total: 100)
                    .tint(manager.isExceeded ? .red : manager.isWarning ? .orange : Color.accentColor)

                if manager.isExceeded {
                    Text("Storage limit exceeded. Consider cleaning up old recordings.")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if manager.isWarning {
                    Text("Approaching storage limit.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Storage Usage")
        }
    }

    private var recommendationsSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remove old audio files")
                        .font(.subheadline)
                    Text("Transcripts will be preserved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "waveform")
                    .foregroundStyle(.blue)
            }

            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete exported files")
                        .font(.subheadline)
                    Text("Re-export anytime from sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "doc.text")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Recommendations")
        }
    }

    private var actionsSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteOldAudio = true
            } label: {
                Label("Clean Up Old Audio", systemImage: "trash")
            }

            Button(role: .destructive) {
                showDeleteExports = true
            } label: {
                Label("Delete All Exports", systemImage: "doc.text.fill")
            }
        } header: {
            Text("Actions")
        } footer: {
            Text("Deleting audio preserves all transcripts and session data.")
        }
    }
}
