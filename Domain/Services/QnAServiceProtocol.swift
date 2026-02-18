import Foundation

struct AnswerResult {
    let segments: [SearchResult]
    let isEmpty: Bool
}

@MainActor
protocol QnAServiceProtocol: AnyObject {
    func answer(question: String, in sessionId: UUID?) -> AnswerResult
}
