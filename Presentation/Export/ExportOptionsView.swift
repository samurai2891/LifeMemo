import SwiftUI

/// Sheet view for selecting export format and content options.
///
/// Presents a form with format picker, content toggles, and an export
/// button that triggers file generation and shows a share sheet.
struct ExportOptionsView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ExportOptionsViewModel

    // MARK: - Init

    init(sessionId: UUID, exportService: EnhancedExportService) {
        _viewModel = StateObject(
            wrappedValue: ExportOptionsViewModel(
                sessionId: sessionId,
                exportService: exportService
            )
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                formatSection
                contentSection
                exportButtonSection
            }
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $viewModel.showShareSheet) {
                if let url = viewModel.exportedURL {
                    ExportShareSheet(activityItems: [url])
                }
            }
            .alert("Export Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Format Section

    private var formatSection: some View {
        Section {
            Picker("Format", selection: $viewModel.options.format) {
                ForEach(ExportOptions.ExportFormat.allCases) { format in
                    Label(format.rawValue, systemImage: format.icon)
                        .tag(format)
                }
            }
            .pickerStyle(.segmented)

            formatDescription
        } header: {
            Text("Format")
        }
    }

    private var formatDescription: some View {
        HStack(spacing: 10) {
            Image(systemName: viewModel.options.format.icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.options.format.rawValue)
                    .font(.subheadline.bold())

                Text(formatDescriptionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var formatDescriptionText: String {
        switch viewModel.options.format {
        case .markdown:
            return "Rich formatting with headers and lists. Compatible with note-taking apps."
        case .text:
            return "Plain text format. Compatible with all text editors."
        case .pdf:
            return "Formatted document with typography. Ready to print or share."
        case .json:
            return "Structured data format. Ideal for programmatic access and data portability."
        }
    }

    // MARK: - Content Section

    private var contentSection: some View {
        Section {
            Toggle(isOn: $viewModel.options.includeMetadata) {
                Label("Session Metadata", systemImage: "info.circle")
            }

            Toggle(isOn: $viewModel.options.includeSummary) {
                Label("Summary", systemImage: "doc.text")
            }

            Toggle(isOn: $viewModel.options.includeKeywords) {
                Label("Keywords", systemImage: "tag")
            }

            Toggle(isOn: $viewModel.options.includeHighlights) {
                Label("Highlights", systemImage: "star")
            }

            Toggle(isOn: $viewModel.options.includeTranscript) {
                Label("Full Transcript", systemImage: "text.alignleft")
            }

            Toggle(isOn: $viewModel.options.includeTimestamps) {
                Label("Timestamps", systemImage: "clock")
            }
        } header: {
            Text("Content")
        } footer: {
            Text("Select which sections to include in the exported file.")
        }
    }

    // MARK: - Export Button Section

    private var exportButtonSection: some View {
        Section {
            Button {
                viewModel.performExport()
            } label: {
                HStack {
                    Spacer()

                    if viewModel.isExporting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 8)
                    }

                    Label(
                        exportButtonTitle,
                        systemImage: "square.and.arrow.up"
                    )
                    .font(.body.bold())

                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .disabled(viewModel.isExporting)
        }
    }

    private var exportButtonTitle: String {
        let ext = viewModel.options.format.fileExtension.uppercased()
        return viewModel.isExporting ? "Exporting..." : "Export as \(ext)"
    }
}

// MARK: - Share Sheet (UIKit bridge)

/// UIKit share sheet wrapper for presenting export file URLs.
private struct ExportShareSheet: UIViewControllerRepresentable {

    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

#if DEBUG
private struct ExportOptionsView_Previews: PreviewProvider {
    static var previews: some View {
        Text("ExportOptionsView requires EnhancedExportService")
    }
}
#endif
