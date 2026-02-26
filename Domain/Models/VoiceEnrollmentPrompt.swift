import Foundation

/// Fixed prompts used for voice enrollment.
struct VoiceEnrollmentPrompt: Identifiable, Codable, Equatable {
    let id: Int
    let styleLabel: String
    let text: String

    static let defaultPrompts: [VoiceEnrollmentPrompt] = [
        VoiceEnrollmentPrompt(id: 1, styleLabel: "通常", text: "今日は天気が良いので、散歩に出かけます。"),
        VoiceEnrollmentPrompt(id: 2, styleLabel: "小声", text: "この内容は静かな場所でゆっくり確認してください。"),
        VoiceEnrollmentPrompt(id: 3, styleLabel: "やや大きめ", text: "次の予定は午後三時から会議室で始まります。"),
        VoiceEnrollmentPrompt(id: 4, styleLabel: "速め", text: "必要な資料は昨日のメールに添付しています。"),
        VoiceEnrollmentPrompt(id: 5, styleLabel: "ゆっくり", text: "重要なポイントを一つずつ順番に整理していきます。"),
        VoiceEnrollmentPrompt(id: 6, styleLabel: "疑問文", text: "この提案の優先順位は本当に今が最適でしょうか。"),
        VoiceEnrollmentPrompt(id: 7, styleLabel: "数字", text: "売上は一月が百二十、二月が百三十五、三月が百五十でした。"),
        VoiceEnrollmentPrompt(id: 8, styleLabel: "固有名詞", text: "新宿、品川、横浜の順で打ち合わせを行います。"),
        VoiceEnrollmentPrompt(id: 9, styleLabel: "子音多め", text: "機能強化計画では検証結果を厳密に記録します。"),
        VoiceEnrollmentPrompt(id: 10, styleLabel: "母音伸ばし", text: "これはとてもわかりやすい説明だと思います。"),
        VoiceEnrollmentPrompt(id: 11, styleLabel: "語尾変化", text: "この件は本日中に完了させます。完了させますか。"),
        VoiceEnrollmentPrompt(id: 12, styleLabel: "自然文", text: "最後に全体を見直して、誤りがないか確認します。")
    ]
}
