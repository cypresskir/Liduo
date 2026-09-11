#!/bin/zsh
set -euo pipefail
liduo_root="$(cd "$(dirname "$0")/.." && pwd)"
liduo_version=2.9.6
liduo_sha=8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606
liduo_archive="$liduo_root/.build/Sparkle-$liduo_version.zip"
liduo_target="$liduo_root/.build/Sparkle-$liduo_version"
mkdir -p "$liduo_root/.build"
if [[ ! -f "$liduo_archive" ]]; then
  liduo_download=$(mktemp "$liduo_root/.build/sparkle-download.XXXXXX")
  trap 'rm -f "$liduo_download"' EXIT
  curl --fail --location --proto '=https' --proto-redir '=https' --retry 2 \
    --connect-timeout 15 --max-time 120 \
    "https://github.com/sparkle-project/Sparkle/releases/download/$liduo_version/Sparkle-for-Swift-Package-Manager.zip" \
    --output "$liduo_download"
  [[ "$(shasum -a 256 "$liduo_download" | cut -d ' ' -f 1)" == "$liduo_sha" ]] || { echo 'Sparkle checksum mismatch' >&2; exit 1; }
  mv "$liduo_download" "$liduo_archive"
fi
[[ "$(shasum -a 256 "$liduo_archive" | cut -d ' ' -f 1)" == "$liduo_sha" ]] || { echo 'Cached Sparkle checksum mismatch' >&2; exit 1; }
if [[ ! -f "$liduo_target/.complete" ]]; then
  ditto -x -k "$liduo_archive" "$liduo_target"
  print -r -- "$liduo_sha" > "$liduo_target/.complete"
fi
echo "Sparkle $liduo_version ready (SHA-256 verified)."
