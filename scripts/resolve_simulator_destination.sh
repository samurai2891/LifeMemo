#!/usr/bin/env bash
set -euo pipefail

# Resolves a runnable iOS simulator destination for xcodebuild.
# Output format:
#   id=<simulator-udid>

PROJECT="${PROJECT:-LifeMemo.xcodeproj}"
SCHEME="${SCHEME:-LifeMemo}"

destinations="$(
  xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -sdk iphonesimulator \
    -showdestinations 2>/dev/null || true
)"

simulator_id="$(
  printf "%s\n" "${destinations}" \
    | sed -n 's/.*platform:iOS Simulator[^,]*, id:\([^,}]*\).*/\1/p' \
    | head -n 1
)"

if [[ -n "${simulator_id}" && "${simulator_id}" != *placeholder* ]]; then
  echo "id=${simulator_id}"
  exit 0
fi

if printf "%s\n" "${destinations}" | grep -q "name:Any iOS Simulator Device"; then
  echo "platform=iOS Simulator,name=Any iOS Simulator Device"
  exit 0
fi

# Final fallback if destination discovery fails.
echo "generic/platform=iOS Simulator"
