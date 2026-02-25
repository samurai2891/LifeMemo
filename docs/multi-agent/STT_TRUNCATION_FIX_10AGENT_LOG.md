# STT Truncation / Realtime Reset Fix - 10 Agent Role Log

Date: 2026-02-26

## Agent 01 - Repro Analyst
- Reconfirmed issue from user report:
  - realtime shows text, but after pause + re-speech previous partial disappears
  - after stop, persisted transcript often keeps only last utterance

## Agent 02 - Pipeline Mapper
- Mapped runtime flow:
  - `LiveTranscriber` (realtime)
  - `ChunkedAudioRecorder` -> `TranscriptionQueueActor`
  - `OnDeviceTranscriber` -> `SessionRepository`

## Agent 03 - Root Cause Investigator (Realtime)
- Identified that `partialText` is overwritten each callback.
- If recognizer resets hypothesis after pause without emitting stable final, prior text can vanish from realtime UI.

## Agent 04 - Root Cause Investigator (Persisted)
- Identified risk that URL recognition may return narrow final hypothesis.
- Existing save path depended on this text and diarization output quality.

## Agent 05 - Realtime Fix Engineer
- Implemented partial rollover handling in `LiveTranscriber`:
  - detect hypothesis reset and commit previous partial before overwrite
  - dedupe near-identical confirmed segments
  - flush current partial on stop/restart
  - added silence-gap-aware rollback detection to catch "prefix-kept but text shrank" resets

## Agent 06 - Recognition Robustness Engineer
- Improved `OnDeviceTranscriber` URL path:
  - keep recognition task strongly referenced
  - enable partial callbacks and merge word segments across callbacks
  - resolve final text using merged fallback when primary looks truncated
  - cancel active recognition task explicitly on timeout

## Agent 07 - Persistence Safety Engineer
- Added completeness evaluator call in `TranscriptionQueueActor`.
- On suspicious truncation, fallback to full transcript persistence (single segment path).

## Agent 08 - Repository Guard Engineer
- Added repository-side fallback guard in `saveTranscriptWithSpeakers` for defense in depth.

## Agent 09 - Test Engineer
- Added regression tests:
  - `TranscriptionCompletenessEvaluatorTests`
  - `SessionRepositoryDiarizationFallbackTests`
  - `LiveTranscriberPartialRolloverTests`
- Added new tests to `scripts/eval_stt.sh`.

## Agent 10 - Verification / Integration Reviewer
- Ran `xcodegen generate` to sync project.
- Build execution in this environment is blocked by:
  - CoreSimulatorService instability
  - Swift `#Preview` macro plugin failure (`PreviewsMacros.SwiftUIView`)
- Confirmed changed STT files are compiled before unrelated preview-macro failure.
