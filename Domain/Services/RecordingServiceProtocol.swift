import Foundation

protocol RecordingServiceProtocol: AnyObject {
    var state: RecordingState { get }
    func startAlwaysOn(languageMode: LanguageMode)
    func stop()
    func addHighlight()
}
