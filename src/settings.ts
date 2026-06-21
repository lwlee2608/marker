type Theme = "light" | "dark";
type ThemeChoice = Theme | "system";

const THEME_KEY = "marker-theme";
const FONT_KEY = "marker-font";
const SIZE_KEY = "marker-font-size";

const FONTS: Record<string, { label: string; stack: string }> = {
  "jetbrains-mono": {
    label: "JetBrains Mono",
    stack:
      '"JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
  },
  "system-mono": {
    label: "System Mono",
    stack: "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace",
  },
  "system-sans": {
    label: "System Sans",
    stack:
      '-apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif',
  },
  serif: {
    label: "Serif",
    stack: 'Georgia, Cambria, "Times New Roman", Times, serif',
  },
};

const DEFAULT_FONT = "jetbrains-mono";
const SIZES = [13, 14, 15, 16, 18, 20];
const DEFAULT_SIZE = 16;

export function initSettings(): void {
  const fontSel = byId<HTMLSelectElement>("font-select");
  const sizeSel = byId<HTMLSelectElement>("size-select");
  const themeSel = byId<HTMLSelectElement>("theme-select");
  const btn = byId<HTMLButtonElement>("settings-btn");
  const panel = byId<HTMLDivElement>("settings-panel");

  // Font
  for (const [key, { label }] of Object.entries(FONTS)) {
    fontSel.add(new Option(label, key));
  }
  const font = localStorage.getItem(FONT_KEY) ?? DEFAULT_FONT;
  fontSel.value = FONTS[font] ? font : DEFAULT_FONT;
  applyFont(fontSel.value);
  fontSel.addEventListener("change", () => {
    applyFont(fontSel.value);
    localStorage.setItem(FONT_KEY, fontSel.value);
  });

  // Size
  for (const px of SIZES) sizeSel.add(new Option(`${px}px`, String(px)));
  const size = Number(localStorage.getItem(SIZE_KEY)) || DEFAULT_SIZE;
  sizeSel.value = SIZES.includes(size) ? String(size) : String(DEFAULT_SIZE);
  applySize(Number(sizeSel.value));
  sizeSel.addEventListener("change", () => {
    applySize(Number(sizeSel.value));
    localStorage.setItem(SIZE_KEY, sizeSel.value);
  });

  // Theme
  const savedTheme = localStorage.getItem(THEME_KEY) as Theme | null;
  themeSel.value = savedTheme ?? "system";
  applyTheme(savedTheme ?? systemTheme());
  themeSel.addEventListener("change", () => {
    const choice = themeSel.value as ThemeChoice;
    if (choice === "system") {
      localStorage.removeItem(THEME_KEY);
      applyTheme(systemTheme());
    } else {
      localStorage.setItem(THEME_KEY, choice);
      applyTheme(choice);
    }
  });
  // follow the OS only while the user hasn't made an explicit choice
  window
    .matchMedia("(prefers-color-scheme: dark)")
    .addEventListener("change", (e) => {
      if (!localStorage.getItem(THEME_KEY)) applyTheme(e.matches ? "dark" : "light");
    });

  // Popover open/close
  const setOpen = (open: boolean) => {
    panel.classList.toggle("open", open);
    btn.setAttribute("aria-expanded", String(open));
  };
  btn.addEventListener("click", (e) => {
    e.stopPropagation();
    setOpen(!panel.classList.contains("open"));
  });
  document.addEventListener("click", (e) => {
    if (!panel.contains(e.target as Node)) setOpen(false);
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") setOpen(false);
  });
}

function applyFont(key: string): void {
  document.documentElement.style.setProperty("--app-font", FONTS[key].stack);
}

function applySize(px: number): void {
  document.documentElement.style.setProperty("--app-font-size", `${px}px`);
}

function applyTheme(theme: Theme): void {
  document.documentElement.setAttribute("data-theme", theme);
}

function systemTheme(): Theme {
  return window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "light";
}

function byId<T extends HTMLElement>(id: string): T {
  const el = document.getElementById(id);
  if (!el) throw new Error(`#${id} not found`);
  return el as T;
}
