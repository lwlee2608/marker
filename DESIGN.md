# marker — Design Doc

A minimal desktop app that opens an existing Markdown (`.md`) file and renders it
prettily. Built with **Rust + Tauri v2**. Markdown → HTML conversion happens in the
Rust backend; the webview only displays the result and handles navigation/theming.

> **Status: implemented (v1).** All milestones below are done. The backend has unit
> tests for the render pipeline (`cargo test`), and the app builds and launches via
> `pnpm tauri dev`. This doc reflects the as-built design; deviations from the
> original plan are called out inline.

## Goals

- Open a `.md` file via: file picker, drag & drop, OS "Open With"/double-click, and CLI arg.
- Render GitHub-flavored Markdown beautifully (tables, task lists, footnotes, etc.).
- Syntax-highlighted fenced code blocks.
- Light/dark theme toggle (default: follow OS) — including the code blocks.
- Auto-generated Table of Contents / outline from headings.
- Live reload: re-render when the open file changes on disk.

## Non-goals

- Editing Markdown (read-only viewer).
- Multi-tab / multi-document management (one file per window for v1).
- Exporting to PDF/HTML, printing, plugins. (Possible future work.)

## Tech Stack

| Layer            | Choice                                       | Why                                                    |
|------------------|----------------------------------------------|--------------------------------------------------------|
| Shell            | Tauri v2                                      | Small binaries, Rust backend, native webview           |
| Frontend         | Vanilla TypeScript + Vite                     | App is simple; no framework needed                     |
| MD → HTML        | `comrak` 0.28                                 | Full GFM support, AST access for TOC                    |
| Code highlight   | `syntect` 5 via a custom class-based adapter  | Server-side highlight emitting `hl-` CSS classes, so light **and** dark code themes both work |
| External links   | `tauri-plugin-opener`                         | Open `http(s)`/`mailto` links in the OS browser        |
| File watching    | `notify-debouncer-full` 0.3 (re-exports `notify`) | Watches the parent dir; debounces + survives atomic-save renames |
| HTML sanitize    | comrak escapes raw HTML (`unsafe_ = false`) + `tagfilter` | Defense against XSS from untrusted files     |

Tauri plugins: `tauri-plugin-dialog` (file picker), `tauri-plugin-fs`,
`tauri-plugin-cli` (CLI args), `tauri-plugin-single-instance` (forward file to a
running instance, desktop-only), `tauri-plugin-opener` (external links).

> **Deviation from plan:** the original doc used comrak's built-in `SyntectAdapter`,
> which bakes one theme's colors inline. To support a real light/dark toggle on code
> blocks, we implement a small custom `SyntaxHighlighterAdapter` that emits class
> names instead, and ship two scoped stylesheets (see *Syntax highlighting* below).

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                       Tauri App (marker)                       │
│                                                                │
│   ┌──────────────────┐             ┌──────────────────┐        │
│   │   WebView (UI)   │   invoke    │   Rust Backend   │        │
│   │ - vanilla TS     │ ──────────▶ │ - commands.rs    │        │
│   │ - inject HTML    │ ◀────────── │ - markdown.rs    │        │
│   │ - TOC sidebar    │   events    │ - watcher.rs     │        │
│   │ - theme toggle   │             │ - app state      │        │
│   └──────────────────┘             └────────┬─────────┘        │
│                                             │                  │
└─────────────────────────────────────────────┴──────────────────┘
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
├─ tsconfig.json
├─ vite.config.ts
├─ examples/
│  └─ sample.md             # demo document for manual testing
├─ src/                      # frontend (TypeScript)
│  ├─ main.ts                # bootstrap, event wiring, invoke calls, ⌘O, css inject
│  ├─ render.ts              # inject HTML, build TOC, scroll-spy, link routing
│  ├─ theme.ts               # light/dark toggle, follow OS
│  └─ styles/
│     ├─ app.css             # layout + theme CSS variables (:root / [data-theme])
│     ├─ markdown.css        # typography for rendered content
│     └─ highlight.css       # code-block structure (token colors injected at runtime)
└─ src-tauri/                # backend (Rust)
   ├─ Cargo.toml
   ├─ build.rs
   ├─ tauri.conf.json        # bundle.fileAssociations for .md, CSP, cli args
   ├─ capabilities/
   │  └─ default.json        # v2 permissions (core + opener)
   ├─ icons/                 # generated by `tauri icon`
   └─ src/
      ├─ main.rs             # entrypoint → marker_lib::run()
      ├─ lib.rs              # builder, plugins, state, CLI capture, RunEvent::Opened
      ├─ commands.rs         # #[tauri::command] handlers + load funnel
      ├─ markdown.rs         # comrak render + class-based syntect + TOC + highlight CSS
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
    text: String,         // heading text (trimmed, for display)
    id: String,           // anchor id (matches the id on the rendered heading)
}
```

### App state

```rust
struct AppState {
    current_path: Mutex<Option<PathBuf>>,
    watcher: Mutex<Option<FileWatcher>>,   // Debouncer<RecommendedWatcher, FileIdMap>; replaced on open
    initial_file: Mutex<Option<String>>,   // path captured at startup, taken once by the UI
    frontend_ready: AtomicBool,            // set true when the UI calls get_initial_file
}
```

> `initial_file` + `frontend_ready` were added beyond the original sketch to
> arbitrate the macOS cold-start vs. already-running open paths (see below).

### Commands (JS → Rust)

| Command             | Signature                                  | Behavior                                                          |
|---------------------|--------------------------------------------|------------------------------------------------------------------|
| `open_file_dialog`  | `() -> Result<Option<DocPayload>>`         | Native picker (`.md`/`.markdown`), then read + render + watch.    |
| `load_file`         | `(path: String) -> Result<DocPayload>`     | Read a known path (drag-drop, CLI, in-app link), render, watch.   |
| `get_initial_file`  | `() -> Option<String>`                     | Path captured at startup; also flags the frontend as ready.       |
| `get_highlight_css` | `() -> String`                             | Syntect token CSS (light + dark, scoped); injected once at startup. |

`load_path` (the shared impl behind `load_file`/`open_file_dialog`, and reused by the
OS-open paths) is the single funnel: canonicalize → `markdown::render_path` → swap the
active watcher to the new path → return payload.

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
comrak parse → AST (GFM extensions: table, strikethrough, tasklist,
   │          autolink, footnotes, tagfilter, header_ids = Some(""))
   ├──▶ walk AST in document order → for each Heading:
   │        collect raw text → Anchorizer::anchorize → TocEntry { level, text, id }
   ▼
comrak format AST → HTML
   - unsafe_ = false       → raw HTML escaped (XSS-safe)
   - custom highlighter    → fenced code blocks get hl- classed spans
   ▼
HTML string
```

**Matching TOC ids to heading ids.** comrak assigns heading `id`s with an
`Anchorizer` while rendering (when `header_ids` is set). We run our own `Anchorizer`
over the headings during the AST walk, in the same document order, applying the same
text-collection rule comrak uses (concatenate `Text` + inline `Code` literals;
soft/line breaks → space). Because the algorithm and order match, our `id`s equal the
ones in the HTML — including the `-1`, `-2` … de-duplication suffixes. We use an empty
`header_ids` prefix so ids are bare slugs (`hello-world`). The displayed `text` is the
same raw text, trimmed.

### Syntax highlighting (class-based)

- A custom `ClassHighlighter` implements comrak's `SyntaxHighlighterAdapter`. For each
  fence it runs syntect's `ClassedHTMLGenerator` with
  `ClassStyle::SpacedPrefixed { prefix: "hl-" }`, emitting `<span class="hl-…">` tokens
  (no inline colors). Language lookup falls back through token → extension → name →
  case-insensitive name → plain text, so fences like ```` ```rust ```` resolve.
- `get_highlight_css()` builds the colors once at startup from syntect's default
  themes: **InspiredGitHub** (light) and **base16-ocean.dark** (dark). Each theme's
  flat class rules are produced via `css_for_theme_with_class_style` and then
  **prefixed** with a scope selector (`:root …` for light, `[data-theme="dark"] …` for
  dark) so the right palette applies per theme without relying on CSS nesting. The
  frontend injects this as a single `<style id="syntect-theme">`.
- `highlight.css` only carries code-block *structure* (padding, scroll, default fg);
  `markdown.css` carries the `pre`/inline-`code` background per theme.

### Live reload (`watcher.rs`)

- One active watcher at a time; opening a new file replaces it (the old `Debouncer`
  drops and stops).
- Uses `notify-debouncer-full` (~200 ms). We watch the **parent directory**
  (NonRecursive) rather than the file itself, then filter debounced events to the
  target path (`same_file`: equal path, else equal canonicalized path, else equal file
  name). Editors save atomically (write temp + rename), which changes the file's inode
  and would break a direct file watch — watching the directory survives it. The
  debouncer's file-id cache root is registered via `cache().add_root(...)`.
- On a debounced change touching the target: re-read, re-render, emit `file-changed`.
  The frontend preserves scroll position so the reader doesn't jump.

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
                             load_path(path)
                                    ▼
        cold start → get_initial_file()   │   running → emit file-opened
```

- **macOS**: file paths arrive through `RunEvent::Opened` in the run loop, not argv.
  We arbitrate cold-start vs. running with `frontend_ready` (set when the UI calls
  `get_initial_file`): if the UI isn't ready yet, store the path in `initial_file` for
  the UI to pull; if it is ready, `load_path` + emit `file-opened`.
- **Windows/Linux**: path comes as a CLI arg, captured at startup via
  `tauri-plugin-cli` (a `source` positional) into `initial_file`.
  `tauri-plugin-single-instance` forwards argv to the existing instance so a second
  double-click reuses the window (loads the file, emits `file-opened`, focuses).
- The `.md`/`.markdown` association is registered under `bundle.fileAssociations` in
  `tauri.conf.json`.

## Frontend Design

Single window, three regions:

```
┌───────────────────────────────────────────────────┐
│  Toolbar:  [Open]          file.md       [theme]  │
├──────────────┬────────────────────────────────────┤
│              │                                    │
│   TOC        │        Rendered Markdown           │
│  (outline)   │        (scrollable content)        │
│   • H1       │                                    │
│    ◦ H2      │                                    │
│              │                                    │
└──────────────┴────────────────────────────────────┘
```

- **Bootstrap** (`main.ts`): init theme; inject highlight CSS via `get_highlight_css`;
  wire the Open button, theme toggle, and **⌘O / Ctrl+O**; subscribe to `file-opened`
  and `file-changed`; set up drag-drop; finally call `get_initial_file` and load it if
  present.
- **Render** (`render.ts`): inject `payload.html` into the content pane; build the TOC
  list from `payload.toc`; set up scroll-spy (IntersectionObserver) to highlight the
  active heading and keep it visible in the sidebar.
- **Link routing** (`render.ts`): intercept clicks in rendered content —
  `#anchor` → smooth-scroll to the element; absolute URL (`http(s)`, `mailto`, …) →
  open in the OS browser via the opener plugin; relative `*.md`/`*.markdown` → resolve
  against the current file's directory and `load_file` it **in-app**.
- **Drag & drop**: `getCurrentWebview().onDragDropEvent()`; on drop, take the first
  `.md`/`.markdown` path and `load_file`.
- **Theme** (`theme.ts`): CSS variables under `:root` / `[data-theme]`; toggle a
  `data-theme` attribute. Default follows `prefers-color-scheme` and tracks OS changes;
  the toggle overrides and persists to `localStorage`.

## Security

- Local files may be untrusted → comrak `unsafe_ = false` (raw HTML/scripts escaped)
  plus the `tagfilter` extension. (If raw HTML is ever desired, pass through `ammonia`.)
- Tauri CSP in `tauri.conf.json` (Tauri augments it with the IPC/asset sources it
  needs):
  ```
  default-src 'self';
  img-src 'self' asset: http://asset.localhost https: data: blob:;
  style-src 'self' 'unsafe-inline';   /* injected syntect <style> */
  font-src 'self' data:;
  script-src 'self';
  connect-src 'self' ipc: http://ipc.localhost ws://localhost:1421
  ```
  `img-src` allows `https:`/`data:` so remote images in docs render (decision below).
- Capabilities are **minimal**: `core:default` + `opener`. The dialog/fs/cli plugins
  are driven from the Rust backend (not via IPC from the webview), so the webview needs
  no permissions for them.

## Build & Distribution

- Dev: `pnpm tauri dev`. Open a file directly: `pnpm tauri dev -- -- examples/sample.md`.
- Release: `pnpm tauri build` → `.dmg`/`.app` (macOS), `.msi`/`.exe` (Windows),
  `.deb`/`.AppImage` (Linux). _(Not yet exercised in CI.)_
- App icons via `tauri icon` (current set is a generated placeholder — replace before
  shipping).
- Code signing/notarization is out of scope for v1 (note for distribution later).

## Key Dependencies (`src-tauri/Cargo.toml`)

```toml
tauri = { version = "2", features = [] }
tauri-plugin-dialog = "2"
tauri-plugin-fs = "2"
tauri-plugin-cli = "2"
tauri-plugin-opener = "2"
comrak = "0.28"                 # syntect feature is on by default
syntect = "5"
notify-debouncer-full = "0.3"   # re-exports `notify` 6
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# desktop-only (not android/ios):
tauri-plugin-single-instance = "2"
```

## Milestones — all done

1. ✅ **Skeleton** — Tauri v2 (vanilla TS) app; `load_file` renders with comrak.
2. ✅ **Open paths** — file picker + drag & drop + CLI arg + `get_initial_file`.
3. ✅ **Pretty** — `markdown.css` typography, syntect highlight, light/dark theme.
4. ✅ **TOC** — AST heading extraction, sidebar, scroll-spy.
5. ✅ **Live reload** — notify debouncer + `file-changed`, preserve scroll.
6. ✅ **OS association** — `fileAssociations`, macOS `RunEvent::Opened`, single-instance.
7. ✅ **Polish & package** — icons, CSP, capabilities. _(`tauri build` per platform not yet run.)_

## Decisions (resolved) & Future

- **Remote images in docs:** *load them* — CSP allows `https:` and `data:` so hosted
  images render. (Minor privacy trade-off: a remote fetch reveals the doc was opened.)
- **Relative links to other `.md` files:** *open in-app* — resolved against the current
  file's directory and loaded in the same window; external links open in the OS browser.
- **Future:** search-in-document, print/export, recent-files list, multiple windows,
  swap placeholder icons, replace `tagfilter`/escaping with `ammonia` if raw HTML is
  ever wanted, exercise `tauri build` in CI.
```
