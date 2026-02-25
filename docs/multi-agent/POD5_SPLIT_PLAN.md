# Pod-5 Large File Split Plan

最終更新: 2026-02-25

## Scope

- 対象:
  - `Infrastructure/Persistence/SessionRepository.swift` (998 lines)
  - `Infrastructure/Persistence/CoreDataStack.swift` (589 lines)
  - `Presentation/SessionDetail/SessionDetailView.swift` (982 lines)
- 目的:
  - 責務ごとの分割
  - 段階PRでの安全な移行
  - 各PRで `build` / `build-for-testing` を維持

## Constraints (facts)

- `SessionRepository` は単一クラス内に多数の機能セクションが集約されている
- `SessionDetailView` は単一ファイルに複数UIセクションと補助Viewが混在している
- Swift のアクセス制御上、`private` メンバーは別ファイル extension へ直接移せない

## PR Plan

### PR-1: SessionRepository read/write split skeleton

- 追加:
  - `Infrastructure/Persistence/SessionRepositoryWriter.swift`
  - `Infrastructure/Persistence/SessionRepositoryReader.swift`
  - `Infrastructure/Persistence/SessionRepositoryInternal.swift`
- 変更:
  - `SessionRepository` の依存（context/fileStore/logger）アクセスを分離可能な形に整理
  - 振る舞い変更なし
- 完了条件:
  - 既存テスト全件通過
  - 振る舞い差分なし

### PR-2: SessionRepository domain-specific modules

- 分割単位:
  - Session lifecycle
  - Chunk lifecycle
  - Transcription
  - Search/export
  - Backup/import
- 目的:
  - セクション単位で責務をファイル分離
  - merge conflict を低減
- 完了条件:
  - `xcodebuild ... build`
  - `xcodebuild ... build-for-testing`

### PR-3: CoreData model builders extraction

- 追加:
  - `Infrastructure/Persistence/ModelBuilders/SessionModelBuilder.swift`
  - `Infrastructure/Persistence/ModelBuilders/ChunkModelBuilder.swift`
  - `Infrastructure/Persistence/ModelBuilders/TranscriptModelBuilder.swift`
- 変更:
  - `CoreDataStack` の entity 定義を builder に分割
  - relationship 設定を専用ヘルパへ移動

### PR-4: SessionDetailView section components

- 追加:
  - `Presentation/SessionDetail/Sections/SessionDetailHeaderSection.swift`
  - `Presentation/SessionDetail/Sections/SessionDetailSummarySection.swift`
  - `Presentation/SessionDetail/Sections/SessionDetailTranscriptSection.swift`
  - `Presentation/SessionDetail/Sections/SessionDetailActionsSection.swift`
- 変更:
  - `SessionDetailView` は組み立て専用へ縮小

### PR-5: SessionDetailView helper views extraction

- 追加:
  - `Presentation/SessionDetail/Components/AnswerSegmentRow.swift`
  - `Presentation/SessionDetail/Components/ChunkStatusRow.swift`
  - `Presentation/SessionDetail/Components/ActionButton.swift`
  - `Presentation/SessionDetail/Components/ShareSheet.swift`
- 変更:
  - 既存UI部品を同等描画で分離

### PR-6: Cleanup and ownership docs

- 追加:
  - `docs/multi-agent/POD5_OWNERSHIP_MAP.md`（責務と担当のマッピング）
- 変更:
  - 不要コメント・重複ヘルパの整理
  - セクション境界の命名規則統一

## Validation per PR

1. `xcodegen generate`
2. `xcodebuild -project LifeMemo.xcodeproj -scheme LifeMemo -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`
3. `xcodebuild -project LifeMemo.xcodeproj -scheme LifeMemo -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build-for-testing`
4. 変更領域のターゲットテスト

## Rollback Rule

- PRごとに1責務に限定し、失敗時は該当PRのみrevert
- `SessionRepository` / `CoreDataStack` / `SessionDetailView` の同時大規模変更は禁止
