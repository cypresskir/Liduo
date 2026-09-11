#!/bin/zsh
set -euo pipefail
liduo_root="$(cd "$(dirname "$0")" && pwd)"
liduo_mode="${1:-check}"
case "$liduo_mode" in
  check|development|release) ;;
  *) echo 'Usage: ./build.sh [check|development|release]' >&2; exit 2 ;;
esac
if [[ "$liduo_mode" != check ]]; then
  : "${LIDUO_TEAM_ID:?Set LIDUO_TEAM_ID to your Apple development team}"
  [[ "$LIDUO_TEAM_ID" =~ '^[A-Z0-9]{10}$' ]] || { echo 'Invalid team ID' >&2; exit 2; }
  : "${LIDUO_SIGN_IDENTITY:?Set LIDUO_SIGN_IDENTITY to a signing certificate name or SHA-1}"
fi
command -v xcodegen >/dev/null || { echo 'Install XcodeGen: brew install xcodegen' >&2; exit 2; }
cd "$liduo_root"
xcodegen generate
liduo_derived="${LIDUO_DERIVED_DATA:-$(mktemp -d "${TMPDIR:-/private/tmp}/LiduoBuild.XXXXXX")}"
xcodebuild -project Liduo.xcodeproj -scheme Liduo -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$liduo_derived" \
  CODE_SIGNING_ALLOWED=NO build
liduo_app="$liduo_derived/Build/Products/Release/Liduo.app"
if [[ "$liduo_mode" == check ]]; then
  echo "Unsigned build for verification: $liduo_app"
  exit 0
fi
liduo_stage="$(mktemp -d "${TMPDIR:-/private/tmp}/LiduoPackage.XXXXXX")"
ditto --noextattr --norsrc "$liduo_app" "$liduo_stage/Liduo.app"
if [[ "$liduo_mode" == release ]]; then
  codesign --force --options runtime --timestamp --sign "$LIDUO_SIGN_IDENTITY" "$liduo_stage/Liduo.app"
  liduo_requirement='anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'
  liduo_suffix='macos-arm64-unnotarized'
else
  codesign --force --options runtime --timestamp=none --sign "$LIDUO_SIGN_IDENTITY" "$liduo_stage/Liduo.app"
  liduo_requirement='anchor apple generic'
  liduo_suffix='local-arm64'
fi
codesign --verify --strict -R "=$liduo_requirement and certificate leaf[subject.OU] = \"$LIDUO_TEAM_ID\"" "$liduo_stage/Liduo.app"
liduo_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$liduo_stage/Liduo.app/Contents/Info.plist")
mkdir -p "$liduo_root/dist"
liduo_output="$liduo_root/dist/Liduo-v${liduo_version}-${liduo_suffix}.zip"
[[ ! -e "$liduo_output" ]] || { echo "Archive already exists: $liduo_output" >&2; exit 2; }
ditto -c -k --norsrc --noextattr --keepParent "$liduo_stage/Liduo.app" "$liduo_output"
echo "Created: $liduo_output"
if [[ "$liduo_mode" == release ]]; then
  echo 'Not ready for public distribution. Run scripts/notarize.sh on this archive first.'
fi
