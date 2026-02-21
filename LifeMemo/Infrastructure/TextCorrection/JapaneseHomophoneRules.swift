import Foundation

/// A group of words sharing the same reading (pronunciation).
struct HomophoneGroup: Sendable {
    let reading: String
    let candidates: [HomophoneCandidate]
}

/// A single candidate within a homophone group.
struct HomophoneCandidate: Sendable {
    let word: String
    let contextPatterns: [ContextPattern]
    let baseFrequency: Double
}

/// Context clues that raise confidence for a particular candidate.
struct ContextPattern: Sendable {
    let precedingWords: Set<String>
    let followingWords: Set<String>
    let confidence: Double
}

/// Homophone groups with contextual disambiguation rules.
/// Focused on errors commonly produced by SFSpeechRecognizer.
enum JapaneseHomophoneRules {

    /// Lookup a homophone group by any member word.
    static func group(containing word: String) -> HomophoneGroup? {
        wordToGroupIndex[word]
    }

    // MARK: - Groups

    static let groups: [String: HomophoneGroup] = {
        var dict: [String: HomophoneGroup] = [:]
        for group in allGroups {
            dict[group.reading] = group
        }
        return dict
    }()

    /// Index from any candidate word to its group for fast lookup.
    static let wordToGroupIndex: [String: HomophoneGroup] = {
        var dict: [String: HomophoneGroup] = [:]
        for group in allGroups {
            for candidate in group.candidates {
                dict[candidate.word] = group
            }
        }
        return dict
    }()

    // MARK: - All groups

    static let allGroups: [HomophoneGroup] = [
        // かいぎ — 会議 vs 会技 (common SFSpeechRecognizer error)
        HomophoneGroup(reading: "かいぎ", candidates: [
            HomophoneCandidate(
                word: "会議",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["定例", "緊急", "臨時", "全体", "部門", "チーム", "取締役"],
                        followingWords: ["室", "資料", "議事", "出席", "参加", "中", "開始", "終了"],
                        confidence: 0.95
                    ),
                ],
                baseFrequency: 0.95
            ),
            HomophoneCandidate(word: "会技", contextPatterns: [], baseFrequency: 0.01),
        ]),

        // かくにん — 確認 vs 核人
        HomophoneGroup(reading: "かくにん", candidates: [
            HomophoneCandidate(
                word: "確認",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["内容", "最終", "事前", "再", "日程", "納期", "出席", "在庫"],
                        followingWords: ["作業", "事項", "済み", "依頼", "結果", "中", "お願い", "ください"],
                        confidence: 0.95
                    ),
                ],
                baseFrequency: 0.95
            ),
            HomophoneCandidate(word: "核人", contextPatterns: [], baseFrequency: 0.01),
        ]),

        // へんかん — 変換 vs 返還
        HomophoneGroup(reading: "へんかん", candidates: [
            HomophoneCandidate(
                word: "変換",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["データ", "文字", "形式", "コード", "数値"],
                        followingWords: ["処理", "テーブル", "規則", "ミス", "エラー"],
                        confidence: 0.90
                    ),
                ],
                baseFrequency: 0.60
            ),
            HomophoneCandidate(
                word: "返還",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["領土", "資金", "保証金", "敷金"],
                        followingWords: ["請求", "手続き", "済み", "期限"],
                        confidence: 0.90
                    ),
                ],
                baseFrequency: 0.40
            ),
        ]),

        // きかん — 期間 vs 機関 vs 器官 vs 帰還
        HomophoneGroup(reading: "きかん", candidates: [
            HomophoneCandidate(
                word: "期間",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["契約", "保証", "試用", "有効", "一定", "対象"],
                        followingWords: ["中", "内", "延長", "短縮", "満了", "限定"],
                        confidence: 0.90
                    ),
                ],
                baseFrequency: 0.50
            ),
            HomophoneCandidate(
                word: "機関",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["金融", "公共", "行政", "研究", "医療", "教育"],
                        followingWords: ["投資", "紙", "決定"],
                        confidence: 0.90
                    ),
                ],
                baseFrequency: 0.30
            ),
            HomophoneCandidate(
                word: "器官",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["内臓", "消化", "呼吸", "感覚"],
                        followingWords: ["移植", "障害", "機能"],
                        confidence: 0.90
                    ),
                ],
                baseFrequency: 0.10
            ),
            HomophoneCandidate(
                word: "帰還",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["宇宙", "地球"],
                        followingWords: ["カプセル"],
                        confidence: 0.90
                    ),
                ],
                baseFrequency: 0.05
            ),
        ]),

        // こうしん — 更新 vs 行進 vs 交信
        HomophoneGroup(reading: "こうしん", candidates: [
            HomophoneCandidate(
                word: "更新",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["契約", "ライセンス", "システム", "データ", "情報", "定期"],
                        followingWords: ["作業", "手続き", "完了", "日", "頻度"],
                        confidence: 0.90
                    ),
                ],
                baseFrequency: 0.70
            ),
            HomophoneCandidate(
                word: "行進",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["軍", "パレード"],
                        followingWords: ["曲"],
                        confidence: 0.85
                    ),
                ],
                baseFrequency: 0.10
            ),
            HomophoneCandidate(
                word: "交信",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["無線", "衛星"],
                        followingWords: ["記録"],
                        confidence: 0.85
                    ),
                ],
                baseFrequency: 0.10
            ),
        ]),

        // けいかく — 計画 vs 経過区
        HomophoneGroup(reading: "けいかく", candidates: [
            HomophoneCandidate(
                word: "計画",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["事業", "開発", "予算", "採用", "販売", "研修", "実施"],
                        followingWords: ["書", "案", "策定", "変更", "見直し", "段階"],
                        confidence: 0.95
                    ),
                ],
                baseFrequency: 0.95
            ),
            HomophoneCandidate(word: "経過区", contextPatterns: [], baseFrequency: 0.01),
        ]),

        // しりょう — 資料 vs 飼料
        HomophoneGroup(reading: "しりょう", candidates: [
            HomophoneCandidate(
                word: "資料",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["会議", "参考", "配布", "提出", "説明", "補足"],
                        followingWords: ["作成", "配布", "確認", "準備", "修正", "送付"],
                        confidence: 0.95
                    ),
                ],
                baseFrequency: 0.90
            ),
            HomophoneCandidate(
                word: "飼料",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["家畜", "動物", "魚"],
                        followingWords: ["メーカー", "コスト", "価格"],
                        confidence: 0.90
                    ),
                ],
                baseFrequency: 0.05
            ),
        ]),

        // たいおう — 対応 vs 大王
        HomophoneGroup(reading: "たいおう", candidates: [
            HomophoneCandidate(
                word: "対応",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["緊急", "顧客", "クレーム", "障害", "バグ", "問題"],
                        followingWords: ["方針", "策", "状況", "完了", "中", "依頼", "お願い"],
                        confidence: 0.95
                    ),
                ],
                baseFrequency: 0.95
            ),
            HomophoneCandidate(word: "大王", contextPatterns: [], baseFrequency: 0.02),
        ]),

        // けんとう — 検討 vs 健闘 vs 見当
        HomophoneGroup(reading: "けんとう", candidates: [
            HomophoneCandidate(
                word: "検討",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["導入", "採用", "実施", "方針", "対策", "提案"],
                        followingWords: ["結果", "事項", "中", "お願い", "ください", "課題"],
                        confidence: 0.90
                    ),
                ],
                baseFrequency: 0.70
            ),
            HomophoneCandidate(
                word: "健闘",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["選手", "チーム"],
                        followingWords: ["を", "した", "祈る"],
                        confidence: 0.80
                    ),
                ],
                baseFrequency: 0.15
            ),
            HomophoneCandidate(
                word: "見当",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: [],
                        followingWords: ["がつかない", "違い", "もつかない"],
                        confidence: 0.85
                    ),
                ],
                baseFrequency: 0.10
            ),
        ]),

        // せいか — 成果 vs 生花 vs 聖火
        HomophoneGroup(reading: "せいか", candidates: [
            HomophoneCandidate(
                word: "成果",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["研究", "業務", "活動", "プロジェクト"],
                        followingWords: ["報告", "物", "発表", "達成"],
                        confidence: 0.90
                    ),
                ],
                baseFrequency: 0.70
            ),
            HomophoneCandidate(
                word: "生花",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["活け", "お"],
                        followingWords: ["教室", "店"],
                        confidence: 0.85
                    ),
                ],
                baseFrequency: 0.10
            ),
            HomophoneCandidate(
                word: "聖火",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["オリンピック"],
                        followingWords: ["リレー", "台", "ランナー"],
                        confidence: 0.90
                    ),
                ],
                baseFrequency: 0.05
            ),
        ]),

        // じっし — 実施 vs 実子
        HomophoneGroup(reading: "じっし", candidates: [
            HomophoneCandidate(
                word: "実施",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["テスト", "研修", "調査", "監査", "計画"],
                        followingWords: ["日", "予定", "計画", "状況", "結果", "済み"],
                        confidence: 0.95
                    ),
                ],
                baseFrequency: 0.95
            ),
            HomophoneCandidate(word: "実子", contextPatterns: [], baseFrequency: 0.02),
        ]),

        // かいぜん — 改善 vs 開戦
        HomophoneGroup(reading: "かいぜん", candidates: [
            HomophoneCandidate(
                word: "改善",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["業務", "品質", "環境", "プロセス"],
                        followingWords: ["策", "提案", "活動", "点", "余地", "報告"],
                        confidence: 0.95
                    ),
                ],
                baseFrequency: 0.90
            ),
            HomophoneCandidate(
                word: "開戦",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["戦争"],
                        followingWords: ["日", "理由"],
                        confidence: 0.85
                    ),
                ],
                baseFrequency: 0.05
            ),
        ]),

        // しょうにん — 承認 vs 商人 vs 証人
        HomophoneGroup(reading: "しょうにん", candidates: [
            HomophoneCandidate(
                word: "承認",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["最終", "部長", "上長", "経費", "稟議"],
                        followingWords: ["依頼", "済み", "フロー", "プロセス", "待ち"],
                        confidence: 0.90
                    ),
                ],
                baseFrequency: 0.60
            ),
            HomophoneCandidate(
                word: "商人",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["大阪"],
                        followingWords: ["魂", "気質"],
                        confidence: 0.80
                    ),
                ],
                baseFrequency: 0.15
            ),
            HomophoneCandidate(
                word: "証人",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["目撃", "参考"],
                        followingWords: ["喚問", "尋問", "保護"],
                        confidence: 0.85
                    ),
                ],
                baseFrequency: 0.15
            ),
        ]),

        // こうか — 効果 vs 硬貨 vs 高架 vs 降下
        HomophoneGroup(reading: "こうか", candidates: [
            HomophoneCandidate(
                word: "効果",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["施策", "改善", "広告", "宣伝", "導入"],
                        followingWords: ["測定", "検証", "的", "あり", "なし", "分析"],
                        confidence: 0.90
                    ),
                ],
                baseFrequency: 0.60
            ),
            HomophoneCandidate(
                word: "硬貨",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["百円", "十円", "五百円"],
                        followingWords: ["枚"],
                        confidence: 0.85
                    ),
                ],
                baseFrequency: 0.10
            ),
            HomophoneCandidate(
                word: "高架",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["鉄道", "高速"],
                        followingWords: ["下", "橋", "道路"],
                        confidence: 0.85
                    ),
                ],
                baseFrequency: 0.10
            ),
            HomophoneCandidate(
                word: "降下",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["気温", "温度", "血圧"],
                        followingWords: ["傾向"],
                        confidence: 0.80
                    ),
                ],
                baseFrequency: 0.10
            ),
        ]),

        // きじ — 記事 vs 生地 vs 雉
        HomophoneGroup(reading: "きじ", candidates: [
            HomophoneCandidate(
                word: "記事",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["新聞", "ニュース", "ブログ", "Web"],
                        followingWords: ["作成", "掲載", "公開", "確認"],
                        confidence: 0.90
                    ),
                ],
                baseFrequency: 0.60
            ),
            HomophoneCandidate(
                word: "生地",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["ピザ", "パン", "布"],
                        followingWords: ["選び", "素材"],
                        confidence: 0.85
                    ),
                ],
                baseFrequency: 0.20
            ),
        ]),

        // ほうこく — 報告 vs 奉告
        HomophoneGroup(reading: "ほうこく", candidates: [
            HomophoneCandidate(
                word: "報告",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["進捗", "状況", "結果", "完了", "障害", "日次", "週次"],
                        followingWords: ["書", "事項", "内容", "資料", "会", "義務"],
                        confidence: 0.95
                    ),
                ],
                baseFrequency: 0.98
            ),
            HomophoneCandidate(word: "奉告", contextPatterns: [], baseFrequency: 0.01),
        ]),

        // かいはつ — 開発 vs 解発
        HomophoneGroup(reading: "かいはつ", candidates: [
            HomophoneCandidate(
                word: "開発",
                contextPatterns: [
                    ContextPattern(
                        precedingWords: ["システム", "ソフトウェア", "商品", "製品", "新規"],
                        followingWords: ["環境", "チーム", "計画", "工程", "費用", "部", "プロジェクト"],
                        confidence: 0.95
                    ),
                ],
                baseFrequency: 0.98
            ),
            HomophoneCandidate(word: "解発", contextPatterns: [], baseFrequency: 0.01),
        ]),
    ]
}
