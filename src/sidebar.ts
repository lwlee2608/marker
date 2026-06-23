const COLLAPSED_KEY = "marker-sidebar-collapsed";
const NARROW_BREAKPOINT = 768;

export function initSidebar(): void {
  const btn = byId<HTMLButtonElement>("sidebar-toggle");

  const saved = localStorage.getItem(COLLAPSED_KEY);
  const collapsed =
    saved === null ? window.innerWidth < NARROW_BREAKPOINT : saved === "true";
  apply(btn, collapsed);

  btn.addEventListener("click", () => toggle(btn));

  window.addEventListener("keydown", (e) => {
    if (e.key !== "[" || e.metaKey || e.ctrlKey || e.altKey) return;
    if (isFormField(e.target)) return;
    e.preventDefault();
    toggle(btn);
  });
}

function toggle(btn: HTMLButtonElement): void {
  const collapsed = !document.body.classList.contains("sidebar-collapsed");
  apply(btn, collapsed);
  localStorage.setItem(COLLAPSED_KEY, String(collapsed));
}

function apply(btn: HTMLButtonElement, collapsed: boolean): void {
  document.body.classList.toggle("sidebar-collapsed", collapsed);
  btn.setAttribute("aria-expanded", String(!collapsed));
  btn.title = collapsed ? "Show sidebar ([)" : "Hide sidebar ([)";
}

function isFormField(target: EventTarget | null): boolean {
  const tag = (target as HTMLElement | null)?.tagName;
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT";
}

function byId<T extends HTMLElement>(id: string): T {
  const el = document.getElementById(id);
  if (!el) throw new Error(`#${id} not found`);
  return el as T;
}
