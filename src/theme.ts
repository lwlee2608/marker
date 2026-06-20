type Theme = "light" | "dark";

const KEY = "marker-theme";

export function initTheme(): void {
  const saved = localStorage.getItem(KEY) as Theme | null;
  apply(saved ?? systemTheme());

  // follow the OS only while the user hasn't made an explicit choice
  window
    .matchMedia("(prefers-color-scheme: dark)")
    .addEventListener("change", (e) => {
      if (!localStorage.getItem(KEY)) apply(e.matches ? "dark" : "light");
    });

  updateIcon();
}

export function toggleTheme(): void {
  const current =
    (document.documentElement.getAttribute("data-theme") as Theme) ??
    systemTheme();
  const next: Theme = current === "dark" ? "light" : "dark";
  apply(next);
  localStorage.setItem(KEY, next);
  updateIcon();
}

function apply(theme: Theme): void {
  document.documentElement.setAttribute("data-theme", theme);
}

function systemTheme(): Theme {
  return window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "light";
}

function updateIcon(): void {
  const btn = document.getElementById("theme-btn");
  if (!btn) return;
  const dark = document.documentElement.getAttribute("data-theme") === "dark";
  btn.textContent = dark ? "☀" : "☾";
}
