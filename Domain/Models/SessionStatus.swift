import Foundation

enum SessionStatus: Int16, Codable {
    case idle = 0
    case recording = 1
    case processing = 2
    case ready = 3
    case error = 4
}
