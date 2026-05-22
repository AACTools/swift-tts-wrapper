#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$ROOT_DIR/.speechmarkdown-version"
TARGET_DIR="$ROOT_DIR/speechmarkdown-swift-package"
REPO="AACTools/speechmarkdown-rust"
ASSET_NAME="speechmarkdown-swift-package.zip"

if [ -f "$VERSION_FILE" ]; then
    PINNED_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
else
    echo "Error: .speechmarkdown-version not found" >&2
    exit 1
fi

VERSION="${1:-$PINNED_VERSION}"
echo "SpeechMarkdown Rust: $VERSION"

if [ -d "$TARGET_DIR" ] && [ -f "$TARGET_DIR/.version" ] && [ "$(cat "$TARGET_DIR/.version")" = "$VERSION" ]; then
    echo "Already at $VERSION, nothing to do."
    exit 0
fi

DOWNLOAD_URL="https://github.com/$REPO/releases/download/$VERSION/$ASSET_NAME"

echo "Downloading $DOWNLOAD_URL ..."
TMP_ZIP="$(mktemp "${TMPDIR:-/tmp}"/speechmarkdown-XXXXXX.zip)"
trap 'rm -f "$TMP_ZIP"' EXIT

curl -fSL -o "$TMP_ZIP" "$DOWNLOAD_URL"

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

echo "Extracting..."
unzip -q "$TMP_ZIP" -d "$TARGET_DIR"

# Handle if zip extracts into a subdirectory
if [ -d "$TARGET_DIR/speechmarkdown-swift-package" ]; then
    mv "$TARGET_DIR/speechmarkdown-swift-package/"* "$TARGET_DIR/"
    rmdir "$TARGET_DIR/speechmarkdown-swift-package"
fi

echo "$VERSION" > "$TARGET_DIR/.version"
echo "Done. SpeechMarkdown $VERSION ready at $TARGET_DIR"
