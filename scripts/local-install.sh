#!/usr/bin/env bash
# Build marker from source and install it locally.
# Supports macOS and Linux. Windows is not supported.
set -euo pipefail

cd "$(dirname "$0")/.."

BIN_DIR="$HOME/.local/bin"

# Verify Tauri's Linux build dependencies (webkit2gtk is the linchpin).
# Detects the package manager and offers to install what's missing.
check_linux_deps() {
  if command -v pkg-config >/dev/null 2>&1 \
     && { pkg-config --exists webkit2gtk-4.1 || pkg-config --exists webkit2gtk-4.0; }; then
    return 0
  fi

  echo "==> Missing Linux build dependencies (webkit2gtk not found)"
  local cmd=""
  if command -v apt-get >/dev/null 2>&1; then
    cmd="sudo apt-get update && sudo apt-get install -y libwebkit2gtk-4.1-dev build-essential curl wget file pkg-config libxdo-dev libssl-dev libayatana-appindicator3-dev librsvg2-dev"
  elif command -v dnf >/dev/null 2>&1; then
    cmd="sudo dnf install -y webkit2gtk4.1-devel openssl-devel curl wget file libappindicator-gtk3-devel librsvg2-devel && sudo dnf group install -y c-development"
  elif command -v pacman >/dev/null 2>&1; then
    cmd="sudo pacman -S --needed --noconfirm webkit2gtk-4.1 base-devel curl wget file openssl appmenu-gtk-module libappindicator-gtk3 librsvg"
  elif command -v zypper >/dev/null 2>&1; then
    cmd="sudo zypper install -y webkit2gtk3-soup2-devel libopenssl-devel curl wget file libappindicator3-1 librsvg-devel && sudo zypper install -y -t pattern devel_basis"
  else
    echo "    Could not detect your package manager. Install Tauri's Linux" >&2
    echo "    prerequisites manually: https://v2.tauri.app/start/prerequisites/" >&2
    exit 1
  fi

  echo "    Install with:"
  echo "      $cmd"
  if [ -t 0 ]; then
    read -r -p "    Run this now? [y/N] " reply
    case "$reply" in
      [yY]*) eval "$cmd" ;;
      *) echo "    Aborted. Install the deps and re-run." >&2; exit 1 ;;
    esac
  else
    echo "    Non-interactive shell; install the deps above and re-run." >&2
    exit 1
  fi
}

# pnpm and the Rust toolchain are required to build, on every OS.
check_toolchain() {
  local missing=""
  command -v pnpm  >/dev/null 2>&1 || missing="$missing pnpm (https://pnpm.io)"
  command -v cargo >/dev/null 2>&1 || missing="$missing rust/cargo (https://rustup.rs)"
  if [ -n "$missing" ]; then
    echo "==> Missing build tools:$missing" >&2
    echo "    Install the above and re-run." >&2
    exit 1
  fi
}

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
  rm -f "$BIN_DIR/marker"  # avoid ETXTBSY if marker is currently running
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
  xdg-mime default marker.desktop text/markdown 2>/dev/null || true
}

OS="$(uname -s)"
case "$OS" in
  Darwin) ;;
  Linux)  check_linux_deps ;;
  *) echo "Unsupported OS: $OS. Only macOS and Linux are supported." >&2; exit 1 ;;
esac

check_toolchain

echo "==> Installing JS dependencies"
pnpm install

# Build only what each installer consumes: macOS needs the .app bundle,
# Linux uses the raw binary (skip deb/rpm/AppImage — slow and AppImage is flaky).
echo "==> Building app (this takes a few minutes on first run)"
case "$OS" in
  Darwin) pnpm tauri build --bundles app; install_macos ;;
  Linux)  pnpm tauri build --no-bundle;   install_linux ;;
esac

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "    NOTE: add $BIN_DIR to your PATH to use 'marker' from anywhere" ;;
esac

echo "==> Done. Open a file with:  marker README.md"
