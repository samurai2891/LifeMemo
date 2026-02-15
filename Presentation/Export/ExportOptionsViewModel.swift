import Foundation

/// ViewModel for the export options screen.
///
/// Manages export options state and triggers exports through the
/// EnhancedExportService, producing a shareable file URL on success.
@MainActor
final class ExportOptionsViewModel: ObservableObject {

    // MARK: - Published State

    @Published var options = ExportOptions.full
    @Published private(set) var isExporting = false
    @Published var exportedURL: URL?
    @Published var errorMessage: String?
    @Published var showShareSheet = false

    // MARK: - Dependencies

    let sessionId: UUID
    private let exportService: EnhancedExportService

    // MARK: - Init

    init(sessionId: UUID, exportService: EnhancedExportService) {
        self.sessionId = sessionId
        self.exportService = exportService
    }

    // MARK: - Actions

    func performExport() {
        guard !isExporting else { return }

        isExporting = true
        errorMessage = nil

        do {
            let url = try exportService.export(
                sessionId: sessionId,
                options: options
            )
            exportedURL = url
            showShareSheet = true
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }

        isExporting = false
    }
}
