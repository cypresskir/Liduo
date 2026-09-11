#!/bin/zsh
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'Usage: ./scripts/build-dmg.sh dist/Liduo-vVERSION-macos-arm64-selfsigned.zip' >&2; exit 2; }
liduo_root="$(cd "$(dirname "$0")/.." && pwd)"
liduo_archive="${1:A}"
[[ -f "$liduo_archive" && "$liduo_archive" == *-macos-arm64-selfsigned.zip ]] || {
  echo 'Expected an existing ZIP from build.sh selfsigned.' >&2; exit 2
}
liduo_output="${liduo_archive%-selfsigned.zip}.dmg"
[[ ! -e "$liduo_output" && ! -e "$liduo_output.sha256" ]] || { echo "Output already exists: $liduo_output" >&2; exit 2; }
command -v uv >/dev/null || { echo 'DMG build tool needed: brew install uv. Users do not need it to install Liduo.' >&2; exit 2; }
liduo_stage="$(mktemp -d "${TMPDIR:-/private/tmp}/LiduoDMG.XXXXXX")"
liduo_mount="$liduo_stage/verify"
trap 'if [[ -d "$liduo_mount/Liduo.app" ]]; then hdiutil detach "$liduo_mount" >/dev/null || true; fi' EXIT
ditto -x -k "$liduo_archive" "$liduo_stage/source"
liduo_app="$liduo_stage/source/Liduo.app"
liduo_plist="$liduo_app/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$liduo_plist")" == local.laplapaw.Liduo ]] || { echo 'Unexpected app identity.' >&2; exit 2; }
liduo_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$liduo_plist")
[[ "${liduo_archive:t}" == "Liduo-v${liduo_version}-macos-arm64-selfsigned.zip" ]] || { echo 'Archive name does not match app version.' >&2; exit 2; }
"$liduo_root/scripts/verify-release-signature.sh" "$liduo_app"
UV_CACHE_DIR="$liduo_root/.build/uv-cache" UV_TOOL_DIR="$liduo_root/.build/uv-tools" \
  uv tool run --from dmgbuild==1.6.7 dmgbuild \
  -s "$liduo_root/installer/dmg/settings.py" \
  -D "app=$liduo_app" -D "assets=$liduo_root/installer/dmg" \
  "Liduo $liduo_version" "$liduo_stage/Liduo.dmg"
hdiutil verify "$liduo_stage/Liduo.dmg"
mkdir "$liduo_mount"
hdiutil attach -readonly -nobrowse -mountpoint "$liduo_mount" "$liduo_stage/Liduo.dmg" >/dev/null
codesign --verify --deep --strict "$liduo_mount/Liduo.app"
liduo_changes=$(/usr/bin/rsync -rlcn --delete --itemize-changes "$liduo_app/" "$liduo_mount/Liduo.app/")
[[ -z "$liduo_changes" ]] || { echo "App contents changed in the DMG: $liduo_changes" >&2; exit 2; }
[[ -L "$liduo_mount/Программы" && "$(readlink "$liduo_mount/Программы")" == /Applications ]] || { echo 'Missing Applications shortcut.' >&2; exit 2; }
cmp "$liduo_root/installer/dmg/install.html" "$liduo_mount/Установка.html"
[[ -f "$liduo_mount/.DS_Store" ]] || { echo 'Missing Finder layout.' >&2; exit 2; }
hdiutil detach "$liduo_mount" >/dev/null
mv "$liduo_stage/Liduo.dmg" "$liduo_output"
(cd "${liduo_output:h}" && shasum -a 256 "${liduo_output:t}" > "${liduo_output:t}.sha256")
echo "Created and verified: $liduo_output"
echo 'Self-signed app: first launch may require Open Anyway in macOS Privacy & Security.'
echo "Build workspace: $liduo_stage"
