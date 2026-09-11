#!/bin/zsh
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'Usage: scripts/verify-release-signature.sh APP' >&2; exit 2; }
liduo_root="$(cd "$(dirname "$0")/.." && pwd)"
liduo_fingerprint=$(/usr/bin/openssl x509 -in "$liduo_root/signing/liduo-release.crt" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
[[ "$liduo_fingerprint" =~ '^[0-9A-Fa-f]{40}$' ]] || { echo 'Invalid release certificate.' >&2; exit 2; }
codesign --verify --deep --strict \
  -R "=identifier \"local.laplapaw.Liduo\" and certificate root = H\"$liduo_fingerprint\"" "$1"
