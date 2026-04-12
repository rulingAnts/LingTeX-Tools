#!/usr/bin/env bash
# ── LingTeX Tools — version bump ─────────────────────────────────────────────
# Updates the version in every config file that embeds it, commits the change,
# and creates an annotated git tag.
#
# Usage:
#   ./bump-version.sh 0.4.0
#
# Files updated:
#   tauri/src-tauri/Cargo.toml
#   tauri/src-tauri/tauri.conf.json
#   extension/chrome/manifest.json
#   extension/firefox/manifest.json

set -euo pipefail

NEW="${1-}"
if [[ -z "$NEW" ]]; then
    echo "Usage: $0 <new-version>   (e.g. $0 0.4.0)"
    exit 1
fi

# Strip leading 'v' if provided
NEW="${NEW#v}"

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "Bumping to $NEW ..."

# ── Cargo.toml (TOML: version = "x.y.z" on its own line) ─────────────────────
sed -i '' "s/^version = \"[^\"]*\"/version = \"$NEW\"/" \
    "$REPO_ROOT/tauri/src-tauri/Cargo.toml"

# ── tauri.conf.json, chrome/manifest.json, firefox/manifest.json (JSON) ──────
for f in \
    "$REPO_ROOT/tauri/src-tauri/tauri.conf.json" \
    "$REPO_ROOT/extension/chrome/manifest.json" \
    "$REPO_ROOT/extension/firefox/manifest.json"
do
    jq --arg v "$NEW" '.version = $v' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

# ── Verify ────────────────────────────────────────────────────────────────────
echo ""
echo "Versions now set to:"
grep '^version' "$REPO_ROOT/tauri/src-tauri/Cargo.toml"
jq -r '"tauri.conf.json:       " + .version' "$REPO_ROOT/tauri/src-tauri/tauri.conf.json"
jq -r '"chrome/manifest.json:  " + .version' "$REPO_ROOT/extension/chrome/manifest.json"
jq -r '"firefox/manifest.json: " + .version' "$REPO_ROOT/extension/firefox/manifest.json"

# ── Commit + tag ──────────────────────────────────────────────────────────────
# --yes flag skips the interactive prompt (used by VS Code task)
YES=false
for arg in "$@"; do [[ "$arg" == "--yes" ]] && YES=true; done

if [[ "$YES" != true ]]; then
    echo ""
    read -r -p "Commit and tag v$NEW? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Files updated but not committed."; exit 0; }
fi

git -C "$REPO_ROOT" add \
    tauri/src-tauri/Cargo.toml \
    tauri/src-tauri/tauri.conf.json \
    extension/chrome/manifest.json \
    extension/firefox/manifest.json
git -C "$REPO_ROOT" commit -m "chore: bump version to $NEW"
git -C "$REPO_ROOT" tag -a "v$NEW" -m "v$NEW"
git -C "$REPO_ROOT" push
git -C "$REPO_ROOT" push origin "v$NEW"
echo ""
echo "Done. GitHub Actions release workflow triggered for v$NEW."
