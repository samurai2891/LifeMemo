import Foundation

protocol ExportServiceProtocol: AnyObject {
    func exportMarkdown(sessionId: UUID) throws -> URL
    func exportText(sessionId: UUID) throws -> URL
}
