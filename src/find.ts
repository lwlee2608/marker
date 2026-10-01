let groups: HTMLElement[][] = [];
let current = 0;

export function initFind(): void {
  const input = byId<HTMLInputElement>("find-input");

  window.addEventListener("keydown", (e) => {
    const mod = e.metaKey || e.ctrlKey;
    const key = e.key.toLowerCase();
    if (mod && key === "f") {
      e.preventDefault();
      open();
    } else if (mod && key === "g" && isOpen()) {
      e.preventDefault();
      step(e.shiftKey ? -1 : 1);
    } else if (e.key === "Escape" && isOpen()) {
      close();
    }
  });

  input.addEventListener("input", () => {
    current = 0;
    search();
    reveal();
  });
  input.addEventListener("keydown", (e) => {
    if (e.key !== "Enter" || e.isComposing) return;
    e.preventDefault();
    step(e.shiftKey ? -1 : 1);
  });

  byId("find-prev").addEventListener("click", () => step(-1));
  byId("find-next").addEventListener("click", () => step(1));
  byId("find-close").addEventListener("click", close);
}

export function refreshFind(): void {
  if (isOpen()) search();
}

function isOpen(): boolean {
  return byId("find-bar").classList.contains("open");
}

function open(): void {
  const input = byId<HTMLInputElement>("find-input");
  if (!isOpen()) {
    byId("find-bar").classList.add("open");
    search();
    reveal();
  }
  input.focus();
  input.select();
}

function close(): void {
  byId("find-bar").classList.remove("open");
  clear();
}

function search(): void {
  clear();
  const query = byId<HTMLInputElement>("find-input").value;
  if (query) groups = highlight(byId("doc"), query);
  current = Math.min(current, Math.max(groups.length - 1, 0));
  groups[current]?.forEach((m) => m.classList.add("current"));
  updateCount(query);
}

function step(dir: number): void {
  if (groups.length === 0) return;
  groups[current].forEach((m) => m.classList.remove("current"));
  current = (current + dir + groups.length) % groups.length;
  groups[current].forEach((m) => m.classList.add("current"));
  updateCount(byId<HTMLInputElement>("find-input").value);
  reveal();
}

function reveal(): void {
  groups[current]?.[0].scrollIntoView({ block: "center" });
}

function updateCount(query: string): void {
  byId("find-count").textContent = !query
    ? ""
    : `${groups.length ? current + 1 : 0} / ${groups.length}`;
}

function clear(): void {
  const parents = new Set<Node>();
  byId("doc")
    .querySelectorAll("mark.find-match")
    .forEach((mark) => {
      parents.add(mark.parentNode!);
      mark.replaceWith(...mark.childNodes);
    });
  parents.forEach((p) => p.normalize());
  groups = [];
}

// Matches may span several text nodes (e.g. syntax-highlighted code), so we
// search the concatenated text and wrap each overlapping piece in its own <mark>.
function highlight(root: HTMLElement, query: string): HTMLElement[][] {
  const nodes: Text[] = [];
  const starts: number[] = [];
  const ends: number[] = [];
  let text = "";
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  while (walker.nextNode()) {
    const node = walker.currentNode as Text;
    if (isBlockGap(node)) {
      text += "\0";
      continue;
    }
    nodes.push(node);
    starts.push(text.length);
    text += node.data;
    ends.push(text.length);
  }

  const pattern = query
    .split(/\s+/)
    .map((w) => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
    .join("\\s+");
  const re = new RegExp(pattern, "gi");
  const matches = [...text.matchAll(re)];

  // Wrap from the end: splitText keeps the prefix in the original node, so
  // offsets of earlier matches stay valid.
  const result: HTMLElement[][] = [];
  let k = nodes.length - 1;
  for (let r = matches.length - 1; r >= 0; r--) {
    const s = matches[r].index!;
    const e = s + matches[r][0].length;
    while (starts[k] >= e) k--;
    const group: HTMLElement[] = [];
    for (let j = k; j >= 0 && ends[j] > s; j--) {
      const from = Math.max(s, starts[j]) - starts[j];
      const to = Math.min(e, ends[j]) - starts[j];
      if (to > from) group.unshift(wrap(nodes[j], from, to));
    }
    result.push(group);
  }
  return result.reverse();
}

const BLOCK =
  /^(P|H[1-6]|UL|OL|LI|PRE|BLOCKQUOTE|TABLE|THEAD|TBODY|TR|TH|TD|HR|SECTION)$/;

function isBlockGap(node: Text): boolean {
  return !node.data.trim() && [node.previousSibling, node.nextSibling].some(isBlock);
}

function isBlock(node: Node | null): boolean {
  return node instanceof Element && BLOCK.test(node.tagName);
}

function wrap(node: Text, from: number, to: number): HTMLElement {
  const target = from > 0 ? node.splitText(from) : node;
  if (to - from < target.length) target.splitText(to - from);
  const mark = document.createElement("mark");
  mark.className = "find-match";
  target.replaceWith(mark);
  mark.appendChild(target);
  return mark;
}

function byId<T extends HTMLElement>(id: string): T {
  const el = document.getElementById(id);
  if (!el) throw new Error(`#${id} not found`);
  return el as T;
}
