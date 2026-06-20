# marker — Sample Document

A quick tour of what **marker** renders. Use the sidebar to jump between
sections, and try toggling the theme (top-right).

## Text formatting

You get **bold**, _italic_, ~~strikethrough~~, `inline code`, and
[external links](https://example.com) that open in your browser.

> Blockquotes are styled with a left border and muted text.
>
> — someone, probably

## Lists & tasks

1. Ordered item one
2. Ordered item two
   - nested unordered
   - another nested

- [x] Render GFM task lists
- [x] Syntax-highlight code
- [ ] World domination

## Code

```rust
fn main() {
    let greeting = "hello, marker";
    println!("{greeting}");
}
```

```python
def fib(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a
```

## Table

| Feature        | Status | Notes                       |
| -------------- | :----: | --------------------------- |
| GFM tables     |   ✅   | with alignment              |
| Footnotes      |   ✅   | see below[^1]               |
| Live reload    |   ✅   | edit this file and save     |

## Footnotes

Here is a statement that needs a citation.[^1]

[^1]: This is the footnote text, rendered at the bottom.

---

That's it — open your own `.md` files via **Open**, drag & drop, or the CLI.
