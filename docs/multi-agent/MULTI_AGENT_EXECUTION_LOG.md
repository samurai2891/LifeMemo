# Multi-Agent Execution Log (19 Roles)

最終更新: 2026-02-25

## Team Allocation

- Agent 01-03: Pod-1 (RT allocation risk)
- Agent 04-06: Pod-2 (`audioLevelStream` policy)
- Agent 07-09: Pod-3 (signing/testability)
- Agent 10-12: Pod-4 (CI portability)
- Agent 13-15: Pod-5 (large-file split plan)
- Agent 16-18: Pod-6 (unused code cleanup) + Pod-7 (warning fix)
- Agent 19: Integration E2E

## Cross-Cutting Baseline

### DoD
- `xcodebuild ... build` が成功すること
- `xcodebuild ... build-for-testing` が成功すること
- 変更対象ユニットテストが成功すること
- CI と `scripts/eval_stt.sh` が固定端末名なしで実行できること
- 新規警告を追加しないこと

### Rollback Steps
1. `git diff --name-only` で影響ファイルを確認
2. Pod単位で差分を分離 (`git add -p` で切り出し可能な粒度を維持)
3. 不具合時は該当Pod差分のみを戻す（他Pod差分は保持）
4. `xcodegen generate` を再実行して `project.pbxproj` を再同期
5. `xcodebuild ... build` と対象テストで復旧確認

### Audio Performance Gate (fact-based)
- `AudioEngineManager.runtimeMetrics().rawBufferCopies == 0` を目標値とする（LiveTranscriberの直接フォワード経路）
- `AudioEngineManager.runtimeMetrics().levelSampleCopies == 0` を目標値とする（`uiLevelPolicy: .disabled`）
- CPU%、処理時間ms、ドロップアウト率の実測値は本リポジトリ内に計測実装が存在しないため、別途デバイス計測が必要

## Pod-1 (Agent 01-03)

### Plan
- RTコールバック内の確保箇所を削減し、配線方式を切替可能にする

### Implement
- `AudioEngineManager` に `rawBufferHandler` と `UILevelProcessingPolicy` を追加
- `AudioEngineManager` に `RuntimeMetrics`（tap callbacks / raw copies / level copies）を追加
- `rawBufferHandler` 利用時は RT 上の `AVAudioPCMBuffer` コピーを回避

### Review
- 既存 `rawBufferStream` 互換性を維持していることを確認
- `uiLevelPolicy == .disabled` 時は UI前処理のサンプル配列コピーが走らないことを確認

### Re-Implement
- ログ出力と `runtimeMetrics()` スナップショットAPIを追加

## Pod-2 (Agent 04-06)

### Plan
- `audioLevelStream` の接続 or 無効化を決定し、CPU増のみの状態を解消

### Implement
- 方針を「未使用経路の無効化」に決定
- `LiveTranscriber` の `AudioEngineManager` 起動で `uiLevelPolicy: .disabled` を固定
- `LiveTranscriber` の中継タスクを除去し、render callback から `ActiveRequestHolder` へ直接フォワード

### Review
- 録音UIの波形は既存どおり `AudioMeterCollector` 駆動であり、今回の方針と整合

### Re-Implement
- コメントを更新し、現在のUI経路が `AudioMeterCollector` 駆動であることを明記

## Pod-3 (Agent 07-09)

### Plan
- `DEVELOPMENT_TEAM` 欠落で `xcodebuild test` が不安定になる構成を統一

### Implement
- `project.yml` に以下を追加:
  - `DEVELOPMENT_TEAM: ""`
  - `CODE_SIGN_STYLE: Automatic`（app target）
  - `"CODE_SIGNING_ALLOWED[sdk=iphonesimulator*]" = NO`
  - `"CODE_SIGNING_REQUIRED[sdk=iphonesimulator*]" = NO`
- `xcodegen generate` で `project.pbxproj` を再生成

### Review
- `project.pbxproj` に simulator 向け signing 無効化と team 空値が反映されていることを確認

### Re-Implement
- 削除ファイル反映のため `xcodegen generate` を再実行

## Pod-4 (Agent 10-12)

### Plan
- `iPhone 17` 固定依存を除去し、実行環境依存を下げる

### Implement
- `scripts/resolve_simulator_destination.sh` を追加
- `.github/workflows/ios.yml` に simulator 自動解決ステップを追加
- `scripts/eval_stt.sh` を自動解決 destination に変更

### Review
- CI とローカルスクリプトが同一解決ロジックを利用する構成を確認

### Re-Implement
- build/test 呼び出しへ `CODE_SIGNING_ALLOWED=NO` / `CODE_SIGNING_REQUIRED=NO` を追加

## Pod-5 (Agent 13-15)

### Plan
- `SessionRepository` / `CoreDataStack` / `SessionDetailView` の分割PR計画を定義

### Implement
- `docs/multi-agent/POD5_SPLIT_PLAN.md` を追加

### Review
- 既存実装を変えずに段階PR化できる粒度（機能同等、ビルド可能）であることを確認

### Re-Implement
- 各PRの完了判定コマンドを明記

## Pod-6 + Pod-7 (Agent 16-18)

### Plan
- Pod-7: `StorageLimitManagerTests.swift` の到達不能分岐警告を除去
- Pod-6: 未使用コード対象を採用/削除で確定

### Implement
- Pod-7: `usagePercentage` ヘルパー導入で定数条件分岐を排除
- Pod-6: 以下を削除して「削除で確定」
  - `Domain/Models/ReleaseGate.swift`
  - `Domain/Models/TranscriptionEvaluation.swift`
  - `Infrastructure/Speech/TranscriptionEvaluator.swift`
  - `LifeMemoTests/TranscriptionEvaluatorTests.swift`
- `scripts/eval_stt.sh` から該当テスト指定を削除

### Review
- 全コード参照検索で `ReleaseGate` / `TranscriptionEvaluation` / `TranscriptionEvaluator` の残存参照がないことを確認

### Re-Implement
- 参照同期のため `xcodegen generate` を再実行

## Integration E2E (Agent 19)

### Plan
- `Pod-1..4` 完了後に統合確認（build/build-for-testing/対象テスト）を実行

### Implement
- 実行コマンド:
  - `xcodebuild -project LifeMemo.xcodeproj -scheme LifeMemo -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`
  - `scripts/eval_stt.sh`
- 観測結果:
  - CoreSimulatorService が不安定で simulator destination が placeholder のみになる環境を確認
  - `scripts/resolve_simulator_destination.sh` はこのケースで `Any iOS Simulator Device` を返すよう対応済み
  - build は Swift preview macro plugin (`PreviewsMacros.SwiftUIView`) の外部実装解決失敗で中断
  - `eval_stt.sh` は `xcodebuild: error: Unable to find a device matching the provided destination specifier` で停止

### Review
- Pod-1..7 変更に起因するコンパイルエラーはログ上で未検出
- 現在の主要ブロッカーは実行環境（CoreSimulator / sandbox macro plugin）

### Re-Implement
- CI/ローカルでの destination 自動解決と simulator signing 無効化は反映済み
- 実機または健全な CoreSimulator 環境で再検証予定
