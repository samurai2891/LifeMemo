import Foundation

enum TranscriptionStatus: Int16, Codable {
    case pending = 0
    case running = 1
    case done = 2
    case failed = 3
}
