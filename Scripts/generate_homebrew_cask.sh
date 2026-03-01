#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <zip-path> <tag> [out-file]" >&2
  echo "Example: $0 dist/OpenScribe-0.1.0.zip v0.1.0 /tmp/openscribe.rb" >&2
  exit 1
fi

ZIP_PATH="$1"
TAG="$2"
OUT_FILE="${3:-}"

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Zip not found: $ZIP_PATH" >&2
  exit 1
fi

if [[ "$TAG" == v* ]]; then
  VERSION="${TAG#v}"
else
  VERSION="$TAG"
fi

SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"

CASK_CONTENT="cask \"openscribe\" do
  version \"$VERSION\"
  sha256 \"$SHA256\"

  url \"https://github.com/streichsbaer/OpenScribe/releases/download/$TAG/OpenScribe-#{version}.zip\"
  name \"OpenScribe\"
  desc \"Native macOS menubar dictation app\"
  homepage \"https://github.com/streichsbaer/OpenScribe\"

  app \"OpenScribe.app\"
end"

if [[ -n "$OUT_FILE" ]]; then
  mkdir -p "$(dirname "$OUT_FILE")"
  printf "%s\n" "$CASK_CONTENT" > "$OUT_FILE"
  echo "[homebrew] wrote $OUT_FILE"
else
  printf "%s\n" "$CASK_CONTENT"
fi
