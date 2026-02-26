#!/usr/bin/env bash
set -euo pipefail

# Runs STT evaluation-related tests on the iOS simulator.
#
# Usage:
#   scripts/eval_stt.sh
#   DESTINATION="id=<simulator-udid>" scripts/eval_stt.sh

PROJECT="${PROJECT:-LifeMemo.xcodeproj}"
SCHEME="${SCHEME:-LifeMemo}"
DEFAULT_DESTINATION="$(
  PROJECT="${PROJECT}" \
  SCHEME="${SCHEME}" \
  scripts/resolve_simulator_destination.sh
)"
DESTINATION="${DESTINATION:-${DEFAULT_DESTINATION}}"

echo "[eval_stt] project=${PROJECT} scheme=${SCHEME}"
echo "[eval_stt] destination=${DESTINATION}"

if [[ "${DESTINATION}" == "generic/platform=iOS Simulator" ]]; then
  echo "[eval_stt] ERROR: No concrete iOS Simulator destination was resolved." >&2
  echo "[eval_stt] Launch or create a simulator device, then rerun." >&2
  exit 70
fi

xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -sdk iphonesimulator \
  -destination "${DESTINATION}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test \
  -only-testing:LifeMemoTests/AHCClustererTests \
  -only-testing:LifeMemoTests/SessionFinalizationStatusTests \
  -only-testing:LifeMemoTests/RecognitionModeTests \
  -only-testing:LifeMemoTests/LiveTranscriberPartialRolloverTests \
  -only-testing:LifeMemoTests/TranscriptionCompletenessEvaluatorTests \
  -only-testing:LifeMemoTests/SessionRepositoryDiarizationFallbackTests
