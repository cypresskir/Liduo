#!/bin/zsh
set -euo pipefail
liduo_root="$(cd "$(dirname "$0")/.." && pwd)"
liduo_suite="${1:-unit}"
case "$liduo_suite" in
  unit|all) ;;
  *) echo 'Usage: ./scripts/test.sh [unit|all]' >&2; exit 2 ;;
esac
command -v xcodegen >/dev/null || { echo 'Install XcodeGen: brew install xcodegen' >&2; exit 2; }
cd "$liduo_root"
./scripts/fetch-sparkle.sh
xcodegen generate
liduo_derived="${LIDUO_DERIVED_DATA:-$(mktemp -d "${TMPDIR:-/private/tmp}/LiduoTests.XXXXXX")}"
liduo_results="${LIDUO_TEST_RESULTS:-$liduo_derived/Tests.xcresult}"
liduo_selection=()
if [[ "$liduo_suite" == unit ]]; then
  liduo_selection=(-only-testing:LiduoTests/EffectTests -only-testing:LiduoTests/CursorTests -only-testing:LiduoTests/UpdateTests)
else
  echo 'All tests require a physical MacBook with an active built-in display; a full-screen animation will appear.'
fi
xcodebuild -project Liduo.xcodeproj -scheme Liduo -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$liduo_derived" \
  -resultBundlePath "$liduo_results" CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES \
  "${liduo_selection[@]}" test
