#!/usr/bin/env bash
# Build marker from source and install it to /Applications (macOS).
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Installing JS dependencies"
pnpm install

echo "==> Building app bundle (this takes a few minutes on first run)"
pnpm tauri build

APP="src-tauri/target/release/bundle/macos/marker.app"
DEST="/Applications/marker.app"

echo "==> Installing to $DEST"
rm -rf "$DEST"
cp -r "$APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Done. Launch 'marker' from Spotlight or run: open -a marker"
