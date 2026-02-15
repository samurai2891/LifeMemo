import Foundation

struct AnswerResult {
    let segments: [SearchResult]
    let isEmpty: Bool
}

protocol QnAServiceProtocol: AnyObject {
    func answer(question: String, in sessionId: UUID?) -> AnswerResult
}
