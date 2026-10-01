export interface HistoryEntry {
  path: string;
  scroll: number;
}

const entries: HistoryEntry[] = [];
let index = -1;

export function visit(path: string, scroll: number): void {
  if (entries[index]?.path === path) return;
  if (index >= 0) entries[index].scroll = scroll;
  entries.splice(index + 1, Infinity, { path, scroll: 0 });
  index++;
}

export function step(delta: number, scroll: number): HistoryEntry | null {
  const next = entries[index + delta];
  if (!next) return null;
  entries[index].scroll = scroll;
  index += delta;
  return next;
}

export function canGoBack(): boolean {
  return index > 0;
}

export function canGoForward(): boolean {
  return index < entries.length - 1;
}
