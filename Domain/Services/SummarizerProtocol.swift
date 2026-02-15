import Foundation

protocol SummarizerProtocol: AnyObject {
    func buildSummaryMarkdown(sessionId: UUID) -> String
}
