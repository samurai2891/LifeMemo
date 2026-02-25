# STT Quality Regression Investigation - 20 Agent Log

Date: 2026-02-26

## Agents 01-05 (Investigation)
- Agent 01 Repro Analyst
  - Confirmed symptom: realtime looks acceptable, persisted transcript contains non-spoken text in early half.
- Agent 02 Pipeline Mapper
  - Traced path: OnDeviceTranscriber -> TranscriptionQueueActor -> SessionRepository.
- Agent 03 Regression Historian
  - Confirmed regression introduced in commit `2cab35d` where URL partial merge fallback was added.
- Agent 04 Root Cause Analyst
  - Found merged key used `(timestamp bucket, duration bucket, substring)` allowing competing words at same time to coexist.
- Agent 05 Evidence Verifier
  - Verified previous implementation (`0203960`) used final primary transcript directly.

## Agents 06-10 (Design)
- Agent 06 Precision Architect
  - Chose precision-first policy: primary final text is source of truth by default.
- Agent 07 Fallback Guard Designer
  - Designed strict fallback gate requiring high alignment and low conflict.
- Agent 08 Data Integrity Designer
  - Ensured selected text source and selected word segments are consistent.
- Agent 09 Diagnostics Designer
  - Added source/conflict/alignment diagnostics for chunk-level observability.
- Agent 10 Queue Integration Designer
  - Extended queue logs with diagnostics fields.

## Agents 11-15 (Implementation)
- Agent 11 STT Core Engineer
  - Reworked merge conflict tracking in `OnDeviceTranscriber`.
- Agent 12 Selection Engineer
  - Implemented conservative resolver with conflict/alignment gates.
- Agent 13 Segment Consistency Engineer
  - Bound final `wordSegments` to the selected text source.
- Agent 14 Diagnostics Engineer
  - Added `TranscriptionTextSource` and `TranscriptionQualitySignals`.
- Agent 15 Logging Engineer
  - Added queue logging for source/conflict/alignment.

## Agents 16-20 (Validation)
- Agent 16 Unit Test Engineer
  - Added resolver regression tests covering conflict rejection and fallback conditions.
- Agent 17 Build Verifier
  - Confirmed build execution still blocked by environment-level preview macro/plugin issues.
- Agent 18 Risk Reviewer
  - Checked fallback behavior is now conservative and precision-biased.
- Agent 19 Quality Reviewer
  - Confirmed the former over-merge path no longer auto-promotes noisy consensus.
- Agent 20 Integration Reviewer
  - Confirmed diagnostics now expose whether fallback happened and why.
