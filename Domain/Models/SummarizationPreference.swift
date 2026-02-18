import Foundation

/// User preferences for summarization, persisted via UserDefaults.
struct SummarizationPreference {
    private static let algorithmKey = "lifememo.summarization.algorithm"
    private static let autoSummarizeKey = "lifememo.summarization.auto"

    static var preferredAlgorithm: SummarizationAlgorithm {
        get {
            guard let raw = UserDefaults.standard.string(forKey: algorithmKey),
                  let algo = SummarizationAlgorithm(rawValue: raw) else {
                return .tfidf
            }
            return algo
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: algorithmKey)
        }
    }

    static var autoSummarize: Bool {
        get { UserDefaults.standard.bool(forKey: autoSummarizeKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoSummarizeKey) }
    }
}
