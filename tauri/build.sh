#!/usr/bin/env bash
# build.sh — build the LingTeX Tools desktop app (Tauri)
#
# Usage:
#   ./build.sh          # production build (cargo tauri build)
#   ./build.sh --dev    # launch dev server (cargo tauri dev)
#   ./build.sh --sync   # only sync core.js (no build)

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

# ── Sync shared core.js ───────────────────────────────────────────────────────
echo "[tauri] syncing core.js from extension/shared/ → src/"
cp "$ROOT/extension/shared/core.js" "$SCRIPT_DIR/src/core.js"

if [[ "$1" == "--sync" ]]; then
    echo "[tauri] sync complete"
    exit 0
fi

# ── Build ─────────────────────────────────────────────────────────────────────
cd "$SCRIPT_DIR/src-tauri"

if [[ "$1" == "--dev" ]]; then
    echo "[tauri] launching dev mode…"
    cargo tauri dev
else
    echo "[tauri] building release…"
    cargo tauri build
fi
