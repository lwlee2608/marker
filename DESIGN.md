# marker — Design Doc

A minimal desktop app that opens an existing Markdown (`.md`) file and renders it
prettily. Built with **Rust + Tauri v2**. Markdown → HTML conversion happens in the
Rust backend; the webview only displays the result and handles navigation/theming.

## Goals

- Open a `.md` file via: file picker, drag & drop, OS "Open With"/double-click, and CLI arg.
- Render GitHub-flavored Markdown beautifully (tables, task lists, footnotes, etc.).
- Syntax-highlighted fenced code blocks.
- Light/dark theme toggle (default: follow OS).
- Auto-generated Table of Contents / outline from headings.
- Live reload: re-render when the open file changes on disk.

## Non-goals

- Editing Markdown (read-only viewer).
- Multi-tab / multi-document management (one file per window for v1).
- Exporting to PDF/HTML, printing, plugins. (Possible future work.)

## Tech Stack

| Layer            | Choice                                  | Why                                            |
|------------------|-----------------------------------------|------------------------------------------------|
| Shell            | Tauri v2                                | Small binaries, Rust backend, native webview   |
| Frontend         | Vanilla TypeScript + Vite               | App is simple; no framework needed             |
| MD → HTML        | `comrak`                                | Full GFM support, AST access for TOC           |
| Code highlight   | `syntect` (via comrak's SyntectAdapter) | Server-side highlight, no JS dep               |
| File watching    | `notify` + `notify-debouncer-full`      | Cross-platform, debounces editor atomic saves  |
| HTML sanitize    | comrak escapes raw HTML (`unsafe=false`)| Defense against XSS from untrusted files       |

Tauri plugins: `tauri-plugin-dialog` (file picker), `tauri-plugin-fs`,
`tauri-plugin-cli` (CLI args), `tauri-plugin-single-instance` (forward file to a
running instance).

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      Tauri App (marker)                      │
│                                                              │
│   ┌──────────────────┐             ┌──────────────────┐      │
│   │   WebView (UI)   │   invoke    │   Rust Backend   │      │
│   │ - vanilla TS     │ ──────────▶ │ - commands.rs    │      │
│   │ - inject HTML    │ ◀────────── │ - markdown.rs    │      │
│   │ - TOC sidebar    │   events    │ - watcher.rs     │      │
│   │ - theme toggle   │             │ - app state      │      │
│   └──────────────────┘             └────────┬─────────┘      │
│                                             │                │
└─────────────────────────────────────────────┴────────────────┘
                                              ▼
                                      filesystem (*.md)
```

The webview never reads files itself — all disk access is in Rust. The frontend
receives ready-to-display HTML plus a structured TOC.

## Project Structure

```
marker/
├─ DESIGN.md
├─ index.html
├─ package.json
├─ vite.config.ts
├─ src/                      # frontend (TypeScript)
│  ├─ main.ts                # bootstrap, event wiring, invoke calls
│  ├─ render.ts              # inject HTML, build TOC, scroll-spy
│  ├─ theme.ts               # light/dark toggle, follow OS
│  └─ styles/
│     ├─ app.css             # layout: toolbar, sidebar, content
│     ├─ markdown.css        # typography for rendered content
│     └─ highlight.css       # code-block theme (or syntect inline styles)
└─ src-tauri/                # backend (Rust)
   ├─ Cargo.toml
   ├─ tauri.conf.json        # incl. bundle.fileAssociations for .md
   ├─ capabilities/          # v2 permissions (dialog, fs, cli, event)
   └─ src/
      ├─ main.rs             # entrypoint → lib::run()
      ├─ lib.rs              # builder, plugins, state, RunEvent::Opened
      ├─ commands.rs         # #[tauri::command] handlers
      ├─ markdown.rs         # comrak render + syntect + TOC extraction
      └─ watcher.rs          # notify debouncer → emits file-changed
```

## Backend Design

### Shared types (serde, sent to frontend)

```rust
struct DocPayload {
    path: String,
    html: String,         // sanitized, ready to inject
    toc: Vec<TocEntry>,
}

struct TocEntry {
    level: u8,            // 1..=6
    text: String,         // heading text
    id: String,           // anchor id (matches header_ids in html)
}
```

### App state

```rust
struct AppState {
    current_path: Mutex<Option<PathBuf>>,
    watcher: Mutex<Option<Debouncer>>,   // active file watcher, replaced on open
}
```

### Commands (JS → Rust)

| Command             | Signature                                  | Behavior                                                          |
|---------------------|--------------------------------------------|------------------------------------------------------------------|
| `open_file_dialog`  | `() -> Option<DocPayload>`                 | Native picker (`.md`/`.markdown`), then read + render + watch.    |
| `load_file`         | `(path: String) -> Result<DocPayload>`     | Read a known path (drag-drop, CLI), render, start watching it.    |
| `get_initial_file`  | `() -> Option<String>`                     | Path captured at startup (CLI arg / OS open), or None.            |

`load_file` is the single funnel: read → `markdown::render(text)` → swap the active
watcher to the new path → return payload.

### Events (Rust → JS)

| Event          | Payload       | When                                                          |
|----------------|---------------|--------------------------------------------------------------|
| `file-opened`  | `DocPayload`  | OS "Open With" while app already running (forwarded to UI).   |
| `file-changed` | `DocPayload`  | Watcher fired after debounce; UI re-renders, keeps scroll.    |

### Markdown pipeline (`markdown.rs`)

```
read .md text
   │
   ▼
comrak parse (GFM extensions: table, strikethrough, tasklist,
   │          autolink, footnotes, header_ids)
   ├──▶ walk AST → collect headings → Vec<TocEntry>
   ▼
comrak render to HTML
   - unsafe = false        → raw HTML escaped (XSS-safe)
   - SyntectAdapter        → fenced code blocks highlighted
   ▼
HTML string
```

Comrak's `header_ids` gives stable anchor ids; the TOC entries reuse those ids so
sidebar clicks can `scrollIntoView` the matching element.

### Live reload (`watcher.rs`)

- One active watcher at a time; opening a new file replaces it.
- Use `notify-debouncer-full` (~150–250 ms). Editors save atomically
  (write temp + rename), which fires several raw events — debouncing collapses them
  and survives the rename.
- On debounced change: re-read, re-render, emit `file-changed`. Frontend preserves
  scroll position so the reader doesn't jump.

### File-open entry points

```
                     ┌──────────────────────────────┐
  double-click /     │  OS launches / forwards path │
  "Open With"  ─────▶│                              │
                     └──────────────┬───────────────┘
  macOS:  RunEvent::Opened { urls } │  (app already running or cold start)
  Win/Linux: argv via single-instance plugin / CLI plugin
                                    ▼
   CLI:  `marker file.md` ───▶  capture path at startup
                                    ▼
                             load_file(path)
                                    ▼
        cold start → get_initial_file()   │   running → emit file-opened
```

- **macOS**: file paths arrive through `RunEvent::Opened` in the run loop, not argv.
  Handle both cold start (store path, frontend pulls via `get_initial_file`) and
  running (emit `file-opened`).
- **Windows/Linux**: path comes as a CLI arg. `tauri-plugin-single-instance`
  forwards argv to the existing instance so a second double-click reuses the window.
- Register the `.md`/`.markdown` association under `bundle.fileAssociations` in
  `tauri.conf.json`.

## Frontend Design

Single window, three regions:

```
┌───────────────────────────────────────────────────┐
│  Toolbar:  [Open]          file.md      [theme]   │
├──────────────┬────────────────────────────────────┤
│              │                                    │
│   TOC        │        Rendered Markdown           │
│  (outline)   │        (scrollable content)        │
│   • H1       │                                    │
│    ◦ H2      │                                    │
│              │                                    │
└──────────────┴────────────────────────────────────┘
```

- **Bootstrap** (`main.ts`): on load call `get_initial_file`; if present, `load_file`.
  Subscribe to `file-opened` and `file-changed`. Wire the Open button, drag-drop, and
  theme toggle.
- **Render** (`render.ts`): inject `payload.html` into the content pane; build the TOC
  list from `payload.toc`; set up scroll-spy to highlight the active heading.
- **Drag & drop**: use Tauri's `getCurrentWebview().onDragDropEvent()`; on drop, take
  the first `.md` path and call `load_file`.
- **Theme** (`theme.ts`): CSS variables on `:root`; toggle a `data-theme` attribute.
  Default follows `prefers-color-scheme`; toggle overrides and persists to
  `localStorage`.

## Security

- Render local files that may be untrusted → keep comrak `unsafe = false` so embedded
  raw HTML/scripts are escaped. (If raw HTML is ever desired, pass through `ammonia`.)
- Tauri CSP in `tauri.conf.json`: no remote scripts; `img-src` may allow `https:`/
  `data:`/`asset:` if remote images in docs should load (decide explicitly).
- Capabilities scoped to only the needed plugins (dialog, fs read, cli, event).

## Build & Distribution

- Dev: `pnpm tauri dev`. Release: `pnpm tauri build` → `.dmg`/`.app` (macOS),
  `.msi`/`.exe` (Windows), `.deb`/`.AppImage` (Linux).
- App icons via `tauri icon`.
- Code signing/notarization is out of scope for v1 (note for distribution later).

## Key Dependencies (`src-tauri/Cargo.toml`)

```toml
tauri = { version = "2", features = [] }
tauri-plugin-dialog = "2"
tauri-plugin-fs = "2"
tauri-plugin-cli = "2"
tauri-plugin-single-instance = "2"
comrak = "0.x"                  # with syntect feature
syntect = "5"
notify = "6"
notify-debouncer-full = "0.x"
serde = { version = "1", features = ["derive"] }
```

## Milestones

1. **Skeleton** — `create-tauri-app` (vanilla TS), window opens, `load_file` renders a
   hardcoded path with comrak (no styling).
2. **Open paths** — file picker + drag & drop + CLI arg + `get_initial_file`.
3. **Pretty** — `markdown.css` typography, syntect highlight, light/dark theme.
4. **TOC** — AST heading extraction, sidebar, scroll-spy.
5. **Live reload** — notify debouncer + `file-changed`, preserve scroll.
6. **OS association** — `fileAssociations`, macOS `RunEvent::Opened`, single-instance.
7. **Polish & package** — icons, CSP review, `tauri build` per platform.

## Open Questions / Future

- Remote images in docs: load them, or block for privacy? (CSP decision.)
- Relative links to other `.md` files: open in-app vs. external browser?
- Future: search-in-document, print/export, recent-files list, multiple windows.
```