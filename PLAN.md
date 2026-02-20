# 波形バー視認性改善計画

## 問題分析

録音中の波形バーの動きが小さく、録音されているかどうかが分かりにくい。

### 原因

`AudioMeterCollector.normalizeDb()` が `pow(10, dB / 20)` で線形変換しているが、通常の会話音量（-25〜-15 dB）では出力が **0.056〜0.178** と非常に小さい。

バー高さ `max(4, level * 80)` に適用すると：

| 音声レベル | dB範囲 | 現在の normalized | 現在のバー高 (80pt中) | 見た目 |
|-----------|--------|------------------|---------------------|--------|
| 静寂 | -60以下 | 0.0 | 4pt (最小) | ほぼ見えない |
| 小声 | -40〜-30 | 0.01〜0.03 | 4pt (最小固定) | 動かない |
| 通常会話 | -25〜-15 | 0.06〜0.18 | 4〜14pt | **ほぼ動かない** |
| 大声 | -10〜-5 | 0.32〜0.56 | 25〜45pt | やっと動く |
| 最大 | 0 | 1.0 | 80pt | 最大 |

**通常の会話では全体の5〜18%しかバーが動かない** → これが「動きが小さい」の根本原因。

## 解決方針

**知覚カーブ（perceptual curve）** を適用して、低〜中音量域の視覚的表現を拡大する。

`pow(linear, 0.4)` カーブを適用した場合の改善効果：

| 音声レベル | 現在のバー高 | **改善後のバー高** | 変化率 |
|-----------|------------|------------------|--------|
| 小声 | 4pt | 4〜8pt | +100% |
| 通常会話 | 4〜14pt | **13〜29pt** | **+225%〜+107%** |
| 大声 | 25〜45pt | 41〜54pt | +64%〜+20% |
| 最大 | 80pt | 80pt | 0% |

通常会話時のバーが **80ptの16〜36%** まで拡大し、明確に動きが見える。

追加で blend 比率を調整し、ピーク値の影響を増やすことで瞬間的な動きをより強調する。

## UI比率への影響

**変更なし。** 以下は一切変えない：
- バーの最大高さ（80pt）
- バーの幅（4pt）
- バーの間隔（3pt）
- バーの本数（30本）
- waveformView の frame(height: 80)
- padding(.horizontal, 32)
- レイアウト構成

変更するのは `AudioMeterCollector` 内の **値の変換ロジックのみ**。

---

## 変更ファイル一覧

| # | ファイル | 変更内容 |
|---|---------|---------|
| 1 | `Infrastructure/Audio/AudioMeterCollector.swift` | 知覚カーブ適用 + blend比率調整 + minDb調整 |
| 2 | `LifeMemoTests/AudioMeterCollectorTests.swift` | 既存テスト更新 + 新テスト追加 |

**RecordingView.swift, RecordingViewModel.swift は変更不要。**

---

## Phase 1: AudioMeterCollector — 知覚カーブ適用

### 1-1. `normalizeDb` メソッドに知覚カーブを追加

```swift
private func normalizeDb(_ db: Float) -> Float {
    guard db > minDb else { return 0 }
    guard db < 0 else { return 1 }
    let linear = pow(10, db / 20)
    // 知覚カーブ: 低〜中音量域を拡大して視認性を向上
    return pow(linear, 0.4)
}
```

### 1-2. blend比率の調整

ピーク値の重みを増やし、瞬間的な音の動きをより強調する：

```swift
// 変更前: normalizedAvg * 0.7 + normalizedPeak * 0.3
// 変更後: ピーク比率を上げて動きを強調
let blended = normalizedAvg * 0.5 + normalizedPeak * 0.5
```

### 1-3. minDb を -50 に調整

感度範囲を狭めることで、より小さな音量変化にも反応させる：

```swift
// 変更前: private let minDb: Float = -60.0
// 変更後:
private let minDb: Float = -50.0
```

---

## Phase 2: テスト更新

### 2-1. 既存テストの期待値を更新

知覚カーブ適用により、0 dB の出力は変わらず 1.0 だが、中間値が変わる：

- `testUpdateNormalizesValues`: 0 dB → `pow(1.0, 0.4)` = 1.0 → 既存アサーション `> 0.9` は引き続きパス
- `testSilenceProducesLowLevel`: -160 dB → 0 → 既存アサーション `< 0.01` はパス

### 2-2. 新テスト追加

```swift
func testNormalConversationProducesVisibleLevel() {
    let collector = AudioMeterCollector()
    // -20 dB（通常会話レベル）
    collector.update(averagePower: -20, peakPower: -15)
    // 知覚カーブ適用後は 0.15 以上のレベルになるべき
    XCTAssertGreaterThan(collector.currentLevel, 0.15,
        "Normal conversation should produce clearly visible meter level")
}

func testQuietSpeechProducesDetectableLevel() {
    let collector = AudioMeterCollector()
    // -35 dB（小声レベル）
    collector.update(averagePower: -35, peakPower: -30)
    // 小声でも検出可能なレベル
    XCTAssertGreaterThan(collector.currentLevel, 0.05,
        "Quiet speech should produce detectable meter level")
}

func testPerceptualCurveExpandsMidRange() {
    let collector = AudioMeterCollector()
    // -15 dB → linear 0.178 → perceptual pow(0.178, 0.4) ≈ 0.37
    collector.update(averagePower: -15, peakPower: -15)
    XCTAssertGreaterThan(collector.currentLevel, 0.30,
        "Mid-range levels should be perceptually amplified")
}
```

---

## 6-Agent チーム構成

| Agent # | タイプ | 担当 | フェーズ |
|---------|--------|------|---------|
| 1 | `planner` | 全体計画策定 + 数値検証 | 事前（完了） |
| 2 | `tdd-guide` | テストファースト: 新テスト作成 → RED確認 | Phase 2 先行 |
| 3 | `Bash` (実装) | AudioMeterCollector.swift の知覚カーブ実装 | Phase 1 |
| 4 | `code-reviewer` | 実装コードのレビュー | Phase 1完了後 |
| 5 | `build-error-resolver` | ビルド検証 + エラー修正 | Phase 1-2完了後 |
| 6 | `go-reviewer` → `security-reviewer` | テスト実行 + 最終検証 | 最終 |

**並列実行:**
- Agent 2 (テスト作成) と Agent 3 (実装) は独立して並列実行可能
- Agent 4 (レビュー) と Agent 5 (ビルド) は実装完了後に並列実行
- Agent 6 は全体完了後に実行

---

## リスク

| リスク | 対策 |
|--------|------|
| カーブが強すぎて静寂時もバーが動く | `minDb = -50` で閾値を引き上げ、静寂時は 0 になるよう保証 |
| 大音量時にバーが天井に張り付く | `pow(x, 0.4)` は x=1.0 で 1.0 を返すので最大値は不変 |
| 既存テストが壊れる | 既存の境界値テスト（0 dB, -160 dB）は変更の影響を受けない |

## 検証手順

1. `xcodebuild build` → ビルド成功
2. `xcodebuild test` → 全テストパス
3. シミュレータで録音画面を開き、通常の声量で話す → バーが明確に動くこと
4. 静寂時 → バーが最小値（4pt）で安定すること
5. 大声時 → バーが大きく振れること（天井まで届く）
