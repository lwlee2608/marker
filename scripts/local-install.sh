#!/usr/bin/env bash
# Build marker from source and install it locally.
# Supports macOS and Linux. Windows is not supported.
set -euo pipefail

cd "$(dirname "$0")/.."

BIN_DIR="$HOME/.local/bin"

install_macos() {
  local app="src-tauri/target/release/bundle/macos/marker.app"
  local dest="/Applications/marker.app"

  echo "==> Installing app to $dest"
  rm -rf "$dest"
  cp -r "$app" "$dest"
  xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true

  echo "==> Installing 'marker' command to $BIN_DIR"
  mkdir -p "$BIN_DIR"
  cat > "$BIN_DIR/marker" <<'EOF'
#!/usr/bin/env bash
# marker — open Markdown files in the marker.app desktop viewer
exec open -a "/Applications/marker.app" "$@"
EOF
  chmod +x "$BIN_DIR/marker"
}

install_linux() {
  local bin="src-tauri/target/release/marker"

  echo "==> Installing 'marker' command to $BIN_DIR"
  mkdir -p "$BIN_DIR"
  cp "$bin" "$BIN_DIR/marker"
  chmod +x "$BIN_DIR/marker"

  echo "==> Installing desktop entry (GUI launcher + .md association)"
  local apps_dir="$HOME/.local/share/applications"
  mkdir -p "$apps_dir"
  cat > "$apps_dir/marker.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=marker
Comment=A minimal Markdown viewer
Exec=$BIN_DIR/marker %f
Terminal=false
Categories=Utility;TextEditor;
MimeType=text/markdown;
EOF
  update-desktop-database "$apps_dir" 2>/dev/null || true
}

echo "==> Installing JS dependencies"
pnpm install

echo "==> Building app bundle (this takes a few minutes on first run)"
pnpm tauri build

case "$(uname -s)" in
  Darwin) install_macos ;;
  Linux)  install_linux ;;
  *) echo "Unsupported OS: $(uname -s). Only macOS and Linux are supported." >&2; exit 1 ;;
esac

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "    NOTE: add $BIN_DIR to your PATH to use 'marker' from anywhere" ;;
esac

echo "==> Done. Open a file with:  marker README.md"
