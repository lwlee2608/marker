import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import { renderDoc, loadPath, openDialog, type DocPayload } from "./render";
import { initTheme, toggleTheme } from "./theme";

async function injectHighlightCss(): Promise<void> {
  try {
    const css = await invoke<string>("get_highlight_css");
    const style = document.createElement("style");
    style.id = "syntect-theme";
    style.textContent = css;
    document.head.appendChild(style);
  } catch (e) {
    console.error("get_highlight_css failed", e);
  }
}

window.addEventListener("DOMContentLoaded", async () => {
  initTheme();
  await injectHighlightCss();

  document.getElementById("open-btn")?.addEventListener("click", () => {
    openDialog();
  });
  document.getElementById("theme-btn")?.addEventListener("click", () => {
    toggleTheme();
  });
  window.addEventListener("keydown", (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "o") {
      e.preventDefault();
      openDialog();
    }
  });

  await listen<DocPayload>("file-changed", (e) => {
    renderDoc(e.payload, { preserveScroll: true });
  });
  await listen<DocPayload>("file-opened", (e) => {
    renderDoc(e.payload);
  });

  getCurrentWebview().onDragDropEvent((event) => {
    if (event.payload.type === "drop") {
      const md = event.payload.paths.find((p) => /\.(md|markdown)$/i.test(p));
      if (md) loadPath(md);
    }
  });

  // CLI arg / OS "Open With" captured at startup (cold start)
  try {
    const initial = await invoke<string | null>("get_initial_file");
    if (initial) await loadPath(initial);
  } catch (e) {
    console.error("get_initial_file failed", e);
  }
});
