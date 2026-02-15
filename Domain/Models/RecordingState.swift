import Foundation

enum RecordingState: Equatable {
    case idle
    case recording(sessionId: UUID)
    case stopping
    case error(message: String)

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var sessionId: UUID? {
        if case let .recording(id) = self { return id }
        return nil
    }
}
