# Multi-Agent 改善 TODO（引き継ぎ用）

最終更新: 2026-02-25  
対象リポジトリ: `LifeMemo`

## 目的
- 指摘済みの7課題を、**各課題2名（合計14名）** の体制で改善する。
- 優先度は `P0 > P1 > P2`。まず録音品質リスクを下げ、その後CI/構造負債を解消する。

## スコープ
- In:
  - 音声処理RT負荷、UI前処理経路の整合、署名/CI実行性、巨大ファイル分割、未使用コード整理、テスト警告解消
  - ビルド/テスト/性能指標による完了判定
- Out:
  - プロダクト仕様変更
  - `DEVELOPMENT_TEAM` の最終値決定（要意思決定）

## 優先度付き TODO

### P0（最優先）
- [x] **Pod-1（Agent 1: RealTime Profiler / Agent 2: Audio Memory Engineer）**  
  `Infrastructure/Audio/AudioEngineManager.swift` と `Infrastructure/Audio/AudioPreprocessor.swift` のレンダースレッド内メモリ確保を計測し、再利用バッファ/RT外移送の実装方針を確定する。
- [x] **Pod-2（Agent 3: Audio Pipeline Integrator / Agent 4: Recording UI Engineer）**  
  `audioLevelStream` を `Presentation/Recording/RecordingViewModel.swift` に接続するか、未使用経路を無効化するかを決定し、CPU増のみの状態を解消する。

### P1
- [x] **Pod-3（Agent 5: Build Config Engineer / Agent 6: Signing & Release Engineer）**  
  `LifeMemo.xcodeproj/project.pbxproj` の署名設定を整理し、`DEVELOPMENT_TEAM` 欠落で `xcodebuild test` が失敗しない構成へ統一する。
- [x] **Pod-4（Agent 7: CI Portability Engineer / Agent 8: Test Infra Engineer）**  
  `.github/workflows/ios.yml` と `scripts/eval_stt.sh` の `iPhone 17` 固定依存を除去し、実行環境依存を下げる。
- [x] **Pod-5（Agent 9: Domain Architect / Agent 10: Refactor Engineer）**  
  巨大ファイルを責務分割する実行計画を作成し、段階的PR単位を定義する。  
  対象: `Infrastructure/Persistence/SessionRepository.swift` / `Infrastructure/Persistence/CoreDataStack.swift` / `Presentation/SessionDetail/SessionDetailView.swift`

### P2
- [x] **Pod-6（Agent 11: Product Alignment Engineer / Agent 12: Code Hygiene Engineer）**  
  未使用コードを「採用して本運用」または「削除」で確定する。  
  対象: `Domain/Models/ReleaseGate.swift` / `Domain/Models/TranscriptionEvaluation.swift` / `Infrastructure/Speech/TranscriptionEvaluator.swift`
- [x] **Pod-7（Agent 13: Test Maintainer / Agent 14: Static Analysis Engineer）**  
  `LifeMemoTests/StorageLimitManagerTests.swift:94` の到達不能分岐警告を修正し、警告ゼロを維持する。

## 横断タスク（全Pod共通）
- [x] 共通DoDを定義する（`build` / `build-for-testing` / 対象テスト / 性能指標）。
- [x] 失敗時ロールバック手順を作成してから実装に着手する。
- [ ] 統合E2Eを実施する（録音開始/停止、55秒再起動、長時間録音、低電力、検索表示、CI）。
- [x] マージ順を固定する: **Pod-1/2 → Pod-3/4 → Pod-5/6/7**。

## 受け入れ基準（案）
- [ ] `xcodebuild ... build` 成功
- [ ] `xcodebuild ... build-for-testing` 成功
- [ ] 変更対象のユニットテスト成功
- [ ] 音声処理でドロップアウト悪化なし（要しきい値）
- [ ] CIワークフローで固定端末依存が解消
- [ ] 新規警告を増やさない（理想は警告ゼロ）

## 要意思決定
- [ ] `DEVELOPMENT_TEAM` の正値
- [x] Pod-2の方針（UI接続を優先 / 一時無効化を優先）
- [ ] 音声性能しきい値（CPU%、処理時間ms、ドロップアウト率）

## 引き継ぎメモ
- 直近確認では `build` と `build-for-testing` は成功。
- `xcodebuild ... test` は実行環境の CoreSimulator 不調や署名設定の影響を受けるため、Pod-3/4で先に基盤整備する。
- 2026-02-25 時点で Pod-1/2/3/4/5/6/7 は実装完了（詳細は `docs/multi-agent/`）。
- この実行環境では CoreSimulatorService 不調により `xcodebuild ... test` の再現実行が不安定。
