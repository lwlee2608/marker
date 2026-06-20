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
    # Linux ships the raw binary (not the AppImage) for parity with
    # scripts/local-install.sh — the AppImage's bundled GTK env is flaky.
    Linux)  PLATFORM=linux; EXT='marker-linux' ;;
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

# The raw binary is dynamically linked against the system webkit2gtk stack.
# Ensure the runtime libs are present (mirrors local-install.sh's
# check_linux_deps, but runtime packages rather than -dev).
check_linux_runtime_deps() {
  # ldconfig lives in /usr/sbin, which is often absent from a non-root PATH
  # (e.g. under `curl … | bash`), so resolve it explicitly. Capture its output
  # instead of piping to `grep -q`: grep's early exit gives ldconfig a SIGPIPE
  # that, under `set -o pipefail`, would be misread as "lib missing".
  local ldconfig libs
  ldconfig="$(command -v ldconfig || echo /sbin/ldconfig)"
  libs="$("$ldconfig" -p 2>/dev/null || true)"
  case "$libs" in
    *libwebkit2gtk-4.1.so*) return 0 ;;
  esac

  echo "==> Missing runtime dependency: webkit2gtk"
  local cmd=""
  if have apt-get; then
    cmd="sudo apt-get update && sudo apt-get install -y libwebkit2gtk-4.1-0 libgtk-3-0 libayatana-appindicator3-1 librsvg2-2"
  elif have dnf; then
    cmd="sudo dnf install -y webkit2gtk4.1 libappindicator-gtk3 librsvg2"
  elif have pacman; then
    cmd="sudo pacman -S --needed --noconfirm webkit2gtk-4.1 libappindicator-gtk3 librsvg"
  elif have zypper; then
    cmd="sudo zypper install -y libwebkit2gtk-4_1-0 libappindicator3-1 librsvg-2-2"
  else
    err "could not detect your package manager; install webkit2gtk manually: https://v2.tauri.app/start/prerequisites/"
  fi

  echo "    Install with:"
  echo "      $cmd"
  if [ -t 0 ]; then
    read -r -p "    Run this now? [y/N] " reply
    case "$reply" in
      [yY]*) eval "$cmd" ;;
      *) err "aborted; install the dep above and re-run" ;;
    esac
  else
    err "non-interactive shell; install the dep above and re-run"
  fi
}

install_linux() {  # asset-url
  check_linux_runtime_deps

  local tmp_bin="$BIN_DIR/marker.tmp.$$"

  echo "==> Downloading $1"
  mkdir -p "$BIN_DIR"
  download "$1" "$tmp_bin"
  rm -f "$BIN_DIR/marker"  # avoid ETXTBSY if marker is currently running
  mv "$tmp_bin" "$BIN_DIR/marker"
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
  xdg-mime default marker.desktop text/markdown 2>/dev/null || true
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
