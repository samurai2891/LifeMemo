import Foundation

@MainActor
protocol SummarizerProtocol: AnyObject {
    func buildSummaryMarkdown(sessionId: UUID) -> String
}
