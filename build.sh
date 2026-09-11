#!/bin/zsh
set -euo pipefail
liduo_root="$(cd "$(dirname "$0")" && pwd)"
liduo_mode="${1:-check}"
case "$liduo_mode" in
  check|development|adhoc|selfsigned|release) ;;
  *) echo 'Usage: ./build.sh [check|development|adhoc|selfsigned|release]' >&2; exit 2 ;;
esac
if [[ "$liduo_mode" == development || "$liduo_mode" == release ]]; then
  : "${LIDUO_TEAM_ID:?Set LIDUO_TEAM_ID to your Apple development team}"
  [[ "$LIDUO_TEAM_ID" =~ '^[A-Z0-9]{10}$' ]] || { echo 'Invalid team ID' >&2; exit 2; }
  : "${LIDUO_SIGN_IDENTITY:?Set LIDUO_SIGN_IDENTITY to a signing certificate name or SHA-1}"
fi
command -v xcodegen >/dev/null || { echo 'Install XcodeGen: brew install xcodegen' >&2; exit 2; }
cd "$liduo_root"
./scripts/fetch-sparkle.sh
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
if [[ "$liduo_mode" == adhoc ]]; then
  liduo_sign_args=(--force --options 0 --timestamp=none --sign -)
  liduo_requirement='identifier "local.laplapaw.Liduo"'
  liduo_suffix='macos-arm64-adhoc'
elif [[ "$liduo_mode" == release ]]; then
  liduo_sign_args=(--force --options runtime --timestamp --sign "$LIDUO_SIGN_IDENTITY")
  liduo_requirement='anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'
  liduo_suffix='macos-arm64-unnotarized'
elif [[ "$liduo_mode" == development ]]; then
  liduo_sign_args=(--force --options runtime --timestamp=none --sign "$LIDUO_SIGN_IDENTITY")
  liduo_requirement='anchor apple generic'
  liduo_suffix='local-arm64'
fi
liduo_sparkle="$liduo_stage/Liduo.app/Contents/Frameworks/Sparkle.framework"
if [[ "$liduo_mode" == selfsigned ]]; then
  ./scripts/sign-selfsigned.sh "$liduo_stage/Liduo.app"
  liduo_suffix='macos-arm64-selfsigned'
else
  for liduo_component in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
    liduo_component_path="$liduo_sparkle/Versions/B/$liduo_component"
    [[ -e "$liduo_component_path" ]] || { echo "Missing Sparkle component: $liduo_component" >&2; exit 2; }
    if [[ "$liduo_component" == XPCServices/Downloader.xpc ]]; then
      codesign "${liduo_sign_args[@]}" --preserve-metadata=entitlements "$liduo_component_path"
    else
      codesign "${liduo_sign_args[@]}" "$liduo_component_path"
    fi
  done
  codesign "${liduo_sign_args[@]}" "$liduo_sparkle"
  codesign "${liduo_sign_args[@]}" "$liduo_stage/Liduo.app"
  if [[ "$liduo_mode" != adhoc ]]; then
    liduo_requirement="$liduo_requirement and certificate leaf[subject.OU] = \"$LIDUO_TEAM_ID\""
  fi
  codesign --verify --deep --strict -R "=$liduo_requirement" "$liduo_stage/Liduo.app"
fi
liduo_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$liduo_stage/Liduo.app/Contents/Info.plist")
mkdir -p "$liduo_root/dist"
liduo_output="$liduo_root/dist/Liduo-v${liduo_version}-${liduo_suffix}.zip"
[[ ! -e "$liduo_output" ]] || { echo "Archive already exists: $liduo_output" >&2; exit 2; }
ditto -c -k --norsrc --noextattr --keepParent "$liduo_stage/Liduo.app" "$liduo_output"
(cd "${liduo_output:h}" && shasum -a 256 "${liduo_output:t}" > "${liduo_output:t}.sha256")
echo "Created: $liduo_output"
if [[ "$liduo_mode" == adhoc ]]; then
  echo 'Ad-hoc build: no Developer ID or Apple notarization. See docs/INSTALLING.md.'
fi
if [[ "$liduo_mode" == release ]]; then
  echo 'Not ready for public distribution. Run scripts/notarize.sh on this archive first.'
fi
