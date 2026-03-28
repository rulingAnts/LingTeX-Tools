#!/usr/bin/env bash
# build.sh — Assemble browser extension packages
#
# Copies shared/ files and docs/core.js into each browser's directory,
# then optionally zips them for distribution.
#
# Usage:
#   ./build.sh            # copy files only
#   ./build.sh --zip      # copy + create .zip archives

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHARED="$SCRIPT_DIR/shared"
BROWSERS=("chrome" "firefox")

# Sync core.js from shared/ (source of truth) out to docs/ and tauri/
cp "$SHARED/core.js" "$ROOT/docs/core.js"
cp "$SHARED/core.js" "$ROOT/tauri/src/core.js"

for BROWSER in "${BROWSERS[@]}"; do
    DEST="$SCRIPT_DIR/$BROWSER"
    echo "→ Building $BROWSER..."

    # Copy shared assets
    cp "$SHARED/core.js"       "$DEST/core.js"
    cp "$SHARED/content.js"    "$DEST/content.js"
    cp "$SHARED/background.js" "$DEST/background.js"
    cp "$SHARED/popup.html"    "$DEST/popup.html"
    cp "$SHARED/popup.js"      "$DEST/popup.js"

    # Copy icons if they exist
    if [ -d "$SHARED/icons" ]; then
        mkdir -p "$DEST/icons"
        cp -r "$SHARED/icons/." "$DEST/icons/"
    fi
done

echo "✓ Shared files copied to all browser directories."

# Optional: zip for distribution
if [[ "$1" == "--zip" ]]; then
    for BROWSER in "${BROWSERS[@]}"; do
        ZIP_NAME="lingtex-tools-$BROWSER.zip"
        (cd "$SCRIPT_DIR/$BROWSER" && zip -r "../$ZIP_NAME" . --exclude "*.DS_Store")
        echo "✓ Created $ZIP_NAME"
    done
fi

echo "Done."
