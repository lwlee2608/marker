import { invoke } from "@tauri-apps/api/core";
import { openUrl } from "@tauri-apps/plugin-opener";

export interface TocEntry {
  level: number;
  text: string;
  id: string;
}

export interface DocPayload {
  path: string;
  html: string;
  toc: TocEntry[];
}

let currentPath = "";
let spy: IntersectionObserver | null = null;

export async function loadPath(path: string): Promise<void> {
  try {
    const payload = await invoke<DocPayload>("load_file", { path });
    renderDoc(payload);
  } catch (e) {
    showError(String(e));
  }
}

export async function openDialog(): Promise<void> {
  try {
    const payload = await invoke<DocPayload | null>("open_file_dialog");
    if (payload) renderDoc(payload);
  } catch (e) {
    showError(String(e));
  }
}

export function renderDoc(
  payload: DocPayload,
  opts: { preserveScroll?: boolean } = {},
): void {
  const content = el("content");
  const doc = el("doc");
  const empty = el("empty");
  const fileName = el("file-name");

  const samePath = payload.path === currentPath;
  const prevScroll = opts.preserveScroll && samePath ? content.scrollTop : 0;

  currentPath = payload.path;
  doc.innerHTML = payload.html;
  empty.style.display = "none";
  doc.style.display = "block";

  const name = baseName(payload.path);
  fileName.textContent = name;
  fileName.title = payload.path;
  document.title = `${name} — marker`;

  buildToc(payload.toc);
  wireLinks(doc);
  setupScrollSpy(content, payload.toc);

  content.scrollTop = prevScroll;
}

function buildToc(toc: TocEntry[]): void {
  const nav = el("toc");
  nav.innerHTML = "";
  if (toc.length === 0) {
    nav.classList.add("is-empty");
    return;
  }
  nav.classList.remove("is-empty");

  const ul = document.createElement("ul");
  for (const entry of toc) {
    const li = document.createElement("li");
    li.className = `toc-h${entry.level}`;
    const a = document.createElement("a");
    a.textContent = entry.text;
    a.href = `#${entry.id}`;
    a.dataset.id = entry.id;
    a.addEventListener("click", (ev) => {
      ev.preventDefault();
      scrollToId(entry.id);
    });
    li.appendChild(a);
    ul.appendChild(li);
  }
  nav.appendChild(ul);
}

function wireLinks(doc: HTMLElement): void {
  doc.querySelectorAll<HTMLAnchorElement>("a[href]").forEach((a) => {
    const href = a.getAttribute("href");
    if (!href) return;

    if (href.startsWith("#")) {
      a.addEventListener("click", (ev) => {
        ev.preventDefault();
        scrollToId(decodeURIComponent(href.slice(1)));
      });
      return;
    }

    const scheme = href.match(/^([a-z][a-z0-9+.-]*):/i)?.[1]?.toLowerCase();
    if (scheme) {
      // absolute URL → only hand known-safe schemes to the OS; block the rest
      // (file:, javascript:, smb:, …) since docs may be untrusted
      a.addEventListener("click", (ev) => {
        ev.preventDefault();
        if (scheme === "http" || scheme === "https" || scheme === "mailto") {
          openUrl(href).catch((e) => console.error("openUrl failed", e));
        } else {
          console.warn(`blocked link with unsupported scheme: ${scheme}:`);
        }
      });
      return;
    }

    if (/\.(md|markdown)(#.*)?$/i.test(href)) {
      // relative link to another Markdown file → open in-app
      a.addEventListener("click", (ev) => {
        ev.preventDefault();
        const rel = href.replace(/[?#].*$/, "");
        loadPath(joinNormalize(dirOf(currentPath), rel));
      });
    }
  });
}

function setupScrollSpy(content: HTMLElement, toc: TocEntry[]): void {
  spy?.disconnect();
  if (toc.length === 0) return;

  const links = new Map<string, HTMLElement>();
  document
    .querySelectorAll<HTMLElement>("#toc a[data-id]")
    .forEach((a) => links.set(a.dataset.id!, a));

  const headings = toc
    .map((t) => document.getElementById(t.id))
    .filter((h): h is HTMLElement => h !== null);
  if (headings.length === 0) return;

  const visible = new Set<string>();
  spy = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) visible.add(entry.target.id);
        else visible.delete(entry.target.id);
      }
      // highlight the first heading (in document order) currently visible
      let activeId: string | null = null;
      for (const t of toc) {
        if (visible.has(t.id)) {
          activeId = t.id;
          break;
        }
      }
      links.forEach((a, id) => a.classList.toggle("active", id === activeId));
      links.get(activeId ?? "")?.scrollIntoView({ block: "nearest" });
    },
    { root: content, rootMargin: "0px 0px -70% 0px", threshold: 0 },
  );
  headings.forEach((h) => spy!.observe(h));
}

function scrollToId(id: string): void {
  const target = document.getElementById(id);
  target?.scrollIntoView({ behavior: "smooth", block: "start" });
}

function showError(message: string): void {
  const doc = el("doc");
  const empty = el("empty");
  empty.style.display = "none";
  doc.style.display = "block";
  doc.innerHTML = "";
  const div = document.createElement("div");
  div.className = "error";
  div.textContent = message;
  doc.appendChild(div);
  el("toc").innerHTML = "";
}

// --- helpers ---

function el(id: string): HTMLElement {
  const node = document.getElementById(id);
  if (!node) throw new Error(`missing element #${id}`);
  return node;
}

function baseName(p: string): string {
  const i = Math.max(p.lastIndexOf("/"), p.lastIndexOf("\\"));
  return i >= 0 ? p.slice(i + 1) : p;
}

function dirOf(p: string): string {
  const i = Math.max(p.lastIndexOf("/"), p.lastIndexOf("\\"));
  return i >= 0 ? p.slice(0, i) : "";
}

function joinNormalize(dir: string, rel: string): string {
  const sep = dir.includes("\\") && !dir.includes("/") ? "\\" : "/";
  const parts = dir.replace(/\\/g, "/").split("/");
  for (const part of rel.replace(/\\/g, "/").split("/")) {
    if (part === "" || part === ".") continue;
    if (part === "..") parts.pop();
    else parts.push(part);
  }
  return parts.join(sep);
}
