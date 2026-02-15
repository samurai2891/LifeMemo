import Foundation

@MainActor
final class ExportService: ExportServiceProtocol {

    // MARK: - Dependencies

    private let repository: SessionRepository
    private let fileStore: FileStore

    // MARK: - Init

    init(repository: SessionRepository, fileStore: FileStore) {
        self.repository = repository
        self.fileStore = fileStore
    }

    // MARK: - ExportServiceProtocol

    func exportMarkdown(sessionId: UUID) throws -> URL {
        let model = repository.getSessionExportModel(sessionId: sessionId)
        let text = MarkdownExporter.make(model: model)
        return try fileStore.writeExport(
            text: text,
            ext: "md",
            suggestedName: model.safeFileName
        )
    }

    func exportText(sessionId: UUID) throws -> URL {
        let model = repository.getSessionExportModel(sessionId: sessionId)
        let text = TextExporter.make(model: model)
        return try fileStore.writeExport(
            text: text,
            ext: "txt",
            suggestedName: model.safeFileName
        )
    }
}
