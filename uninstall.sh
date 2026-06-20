#!/usr/bin/env bash
# marker uninstaller — remove what install.sh / scripts/local-install.sh installed.
#
#   curl -fsSL https://raw.githubusercontent.com/lwlee2608/marker/main/uninstall.sh | bash
#
# Supports macOS and Linux.
set -euo pipefail

BIN_DIR="$HOME/.local/bin"

uninstall_macos() {
  rm -rf "/Applications/marker.app"
  rm -f "$BIN_DIR/marker"
}

uninstall_linux() {
  rm -f "$BIN_DIR/marker"
  rm -rf "$HOME/.local/lib/marker"
  local apps_dir="$HOME/.local/share/applications"
  rm -f "$apps_dir/marker.desktop"
  update-desktop-database "$apps_dir" 2>/dev/null || true
}

echo "==> Removing marker"
case "$(uname -s)" in
  Darwin) uninstall_macos ;;
  Linux)  uninstall_linux ;;
  *) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

echo "==> Done."
