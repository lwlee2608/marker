import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import {
  openDoc,
  reloadDoc,
  loadPath,
  openDialog,
  go,
  type DocPayload,
} from "./render";
import { initFind } from "./find";
import { initSettings } from "./settings";
import { initSidebar, isFormField } from "./sidebar";

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
  initSettings();
  initSidebar();
  initFind();
  await injectHighlightCss();

  document.getElementById("open-btn")?.addEventListener("click", () => {
    openDialog();
  });
  document.getElementById("back-btn")?.addEventListener("click", () => go(-1));
  document
    .getElementById("forward-btn")
    ?.addEventListener("click", () => go(1));
  window.addEventListener("keydown", (e) => {
    const mod = e.metaKey || e.ctrlKey;
    if (mod && e.key.toLowerCase() === "o") {
      e.preventDefault();
      openDialog();
    } else if (e.altKey && isFormField(e.target)) {
      return;
    } else if ((mod && e.key === "[") || (e.altKey && e.key === "ArrowLeft")) {
      e.preventDefault();
      go(-1);
    } else if ((mod && e.key === "]") || (e.altKey && e.key === "ArrowRight")) {
      e.preventDefault();
      go(1);
    }
  });
  window.addEventListener("mouseup", (e) => {
    if (e.button !== 3 && e.button !== 4) return;
    e.preventDefault();
    go(e.button === 3 ? -1 : 1);
  });

  await listen<DocPayload>("file-changed", (e) => {
    reloadDoc(e.payload);
  });
  await listen<DocPayload>("file-opened", (e) => {
    openDoc(e.payload);
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
