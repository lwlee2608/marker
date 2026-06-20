#!/usr/bin/env bash
# marker installer — download the latest prebuilt release and install it.
#
#   curl -fsSL https://raw.githubusercontent.com/lwlee2608/marker/main/install.sh | bash
#
# Set MARKER_VERSION=vX.Y.Z to install a specific tag (default: latest).
# Supports macOS and Linux. Windows is not supported.
set -euo pipefail

REPO="lwlee2608/marker"
BIN_DIR="$HOME/.local/bin"
VERSION="${MARKER_VERSION:-latest}"

err()  { echo "error: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

fetch() {  # url -> stdout
  if have curl; then curl -fsSL "$1"
  elif have wget; then wget -qO- "$1"
  else err "need curl or wget"; fi
}

download() {  # url file
  if have curl; then curl -fsSL -o "$2" "$1"
  elif have wget; then wget -qO "$2" "$1"
  else err "need curl or wget"; fi
}

detect() {
  case "$(uname -s)" in
    Darwin) PLATFORM=macos; EXT='\.dmg$' ;;
    Linux)  PLATFORM=linux; EXT='\.AppImage$' ;;
    *) err "unsupported OS: $(uname -s) (only macOS and Linux are supported)" ;;
  esac
  case "$(uname -m)" in
    arm64|aarch64) ARCH_RE='aarch64|arm64' ;;
    x86_64|amd64)  ARCH_RE='x64|x86_64|amd64' ;;
    *) err "unsupported architecture: $(uname -m)" ;;
  esac
}

release_url() {
  if [ "$VERSION" = latest ]; then
    echo "https://api.github.com/repos/$REPO/releases/latest"
  else
    echo "https://api.github.com/repos/$REPO/releases/tags/$VERSION"
  fi
}

# Print the download URL of the asset matching this OS + arch.
pick_asset() {
  local json urls
  json="$(fetch "$(release_url)")" || err "could not query GitHub releases for $REPO"
  urls="$(printf '%s' "$json" \
    | grep -o '"browser_download_url"[: ]*"[^"]*"' \
    | sed 's/.*"\(https[^"]*\)"/\1/')"
  [ -n "$urls" ] || err "no assets in release '$VERSION' (is it published, not a draft?)"
  printf '%s\n' "$urls" | grep -Ei "$EXT" | grep -Ei "$ARCH_RE" | head -1 || true
}

install_shim_macos() {
  mkdir -p "$BIN_DIR"
  cat > "$BIN_DIR/marker" <<'EOF'
#!/usr/bin/env bash
# marker — open Markdown files in the marker.app desktop viewer
exec open -a "/Applications/marker.app" "$@"
EOF
  chmod +x "$BIN_DIR/marker"
}

install_macos() {  # asset-url
  local tmp dmg mount app
  tmp="$(mktemp -d)"; dmg="$tmp/marker.dmg"
  echo "==> Downloading $1"
  download "$1" "$dmg"
  echo "==> Installing to /Applications"
  mount="$(hdiutil attach -nobrowse -readonly "$dmg" | grep -o '/Volumes/.*' | tail -1)"
  app="$(ls -d "$mount"/*.app 2>/dev/null | head -1)"
  [ -n "$app" ] || { hdiutil detach "$mount" >/dev/null 2>&1 || true; err "no .app found inside dmg"; }
  rm -rf "/Applications/marker.app"
  cp -R "$app" "/Applications/marker.app"
  hdiutil detach "$mount" >/dev/null 2>&1 || true
  xattr -dr com.apple.quarantine "/Applications/marker.app" 2>/dev/null || true
  install_shim_macos
  rm -rf "$tmp"
}

install_linux() {  # asset-url
  echo "==> Downloading $1"
  mkdir -p "$BIN_DIR"
  download "$1" "$BIN_DIR/marker"
  chmod +x "$BIN_DIR/marker"

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

main() {
  detect
  local asset
  asset="$(pick_asset)"
  [ -n "$asset" ] || err "no $PLATFORM asset for $(uname -m) in release '$VERSION'"

  case "$PLATFORM" in
    macos) install_macos "$asset" ;;
    linux) install_linux "$asset" ;;
  esac

  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "    NOTE: add $BIN_DIR to your PATH to use 'marker' from anywhere" ;;
  esac
  echo "==> Done. Open a file with:  marker README.md"
}

main "$@"
