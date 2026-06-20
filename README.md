# marker

A minimal desktop app that opens a Markdown (`.md`) file and renders it prettily.
Built with **Rust + Tauri v2**. GitHub-flavored Markdown, syntax-highlighted code,
light/dark themes, an auto-generated outline, and live reload on file change.

Supports **macOS** and **Linux**. Windows is not supported.

## Install

### Quick install (prebuilt)

Downloads the latest release and installs it — no toolchain needed:

```sh
curl -fsSL https://raw.githubusercontent.com/lwlee2608/marker/main/install.sh | bash
```

- **macOS** → `marker.app` in `/Applications`
- **Linux** → an AppImage in `~/.local/bin`

Pin a specific version with `MARKER_VERSION=v0.1.0 ...`. If `~/.local/bin` isn't on
your `PATH`, the installer tells you to add it.

### Build from source

Requires [Rust](https://rustup.rs), [Node](https://nodejs.org), and
[pnpm](https://pnpm.io). On Linux the script checks for Tauri's `webkit2gtk` build
dependencies and offers to install them.

```sh
git clone https://github.com/lwlee2608/marker.git
cd marker
./scripts/local-install.sh
```

## Usage

```sh
marker README.md      # open a file
marker                # launch with the file picker
```

You can also open files via drag & drop, the in-app picker, or your OS
"Open With" / double-click (the app registers `.md` and `.markdown`).

## Development

```sh
pnpm install
pnpm tauri dev        # run in dev mode with hot reload
cargo test --manifest-path src-tauri/Cargo.toml   # backend tests
```

See [DESIGN.md](DESIGN.md) for architecture and design decisions.
