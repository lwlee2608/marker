use std::collections::HashMap;
use std::io::{self, Write};
use std::path::Path;
use std::sync::OnceLock;

use comrak::adapters::SyntaxHighlighterAdapter;
use comrak::nodes::{AstNode, NodeValue};
use comrak::{format_html_with_plugins, parse_document, Anchorizer, Arena, Options, Plugins};
use serde::Serialize;
use syntect::highlighting::ThemeSet;
use syntect::html::{css_for_theme_with_class_style, ClassStyle, ClassedHTMLGenerator};
use syntect::parsing::{SyntaxReference, SyntaxSet};
use syntect::util::LinesWithEndings;

const CLASS_STYLE: ClassStyle = ClassStyle::SpacedPrefixed { prefix: "hl-" };

#[derive(Serialize, Clone)]
pub struct TocEntry {
    pub level: u8,
    pub text: String,
    pub id: String,
}

#[derive(Serialize, Clone)]
pub struct DocPayload {
    pub path: String,
    pub html: String,
    pub toc: Vec<TocEntry>,
}

pub fn render(text: &str, path: &str) -> DocPayload {
    let arena = Arena::new();
    let opts = options();
    let root = parse_document(&arena, text, &opts);

    let toc = collect_toc(root);

    let highlighter = ClassHighlighter::new();
    let mut plugins = Plugins::default();
    plugins.render.codefence_syntax_highlighter = Some(&highlighter);

    let mut out = Vec::new();
    format_html_with_plugins(root, &opts, &mut out, &plugins).expect("comrak render");
    let html = String::from_utf8(out).unwrap_or_default();

    DocPayload {
        path: path.to_string(),
        html,
        toc,
    }
}

pub fn render_path(path: &Path) -> Result<DocPayload, String> {
    let text = std::fs::read_to_string(path)
        .map_err(|e| format!("Failed to read {}: {e}", path.display()))?;
    Ok(render(&text, &path.to_string_lossy()))
}

fn options() -> Options<'static> {
    let mut o = Options::default();
    o.extension.table = true;
    o.extension.strikethrough = true;
    o.extension.tasklist = true;
    o.extension.autolink = true;
    o.extension.footnotes = true;
    o.extension.tagfilter = true;
    o.extension.header_ids = Some(String::new());
    o.render.unsafe_ = false; // escape raw HTML/script in untrusted files
    o
}

fn collect_toc<'a>(root: &'a AstNode<'a>) -> Vec<TocEntry> {
    let mut toc = Vec::new();
    let mut anchorizer = Anchorizer::new();
    for node in root.descendants() {
        if let NodeValue::Heading(h) = &node.data.borrow().value {
            // anchorize the raw (untrimmed) text so ids match comrak's rendered HTML
            let mut raw = String::new();
            collect_text(node, &mut raw);
            let id = anchorizer.anchorize(raw.clone());
            toc.push(TocEntry {
                level: h.level,
                text: raw.trim().to_string(),
                id,
            });
        }
    }
    toc
}

fn collect_text<'a>(node: &'a AstNode<'a>, out: &mut String) {
    match &node.data.borrow().value {
        NodeValue::Text(t) => out.push_str(t),
        NodeValue::Code(c) => out.push_str(&c.literal),
        NodeValue::LineBreak | NodeValue::SoftBreak => out.push(' '),
        _ => {
            for child in node.children() {
                collect_text(child, out);
            }
        }
    }
}

/// Two scoped stylesheets (light under `:root`, dark under `[data-theme="dark"]`)
/// for the `hl-` token classes emitted by the highlighter. Injected once at startup.
pub fn highlight_css() -> String {
    let ts = ThemeSet::load_defaults();
    let light = ts
        .themes
        .get("InspiredGitHub")
        .and_then(|t| css_for_theme_with_class_style(t, CLASS_STYLE).ok())
        .unwrap_or_default();
    let dark = ts
        .themes
        .get("base16-ocean.dark")
        .and_then(|t| css_for_theme_with_class_style(t, CLASS_STYLE).ok())
        .unwrap_or_default();

    let mut css = scope_css(&light, ":root");
    css.push('\n');
    css.push_str(&scope_css(&dark, "[data-theme=\"dark\"]"));
    css
}

/// Prefix every rule's selector with `scope` so syntect's flat class rules only
/// apply within the chosen theme. (Avoids relying on CSS nesting.)
fn scope_css(css: &str, scope: &str) -> String {
    let mut out = String::new();
    for rule in css.split_inclusive('}') {
        match rule.find('{') {
            Some(brace) => {
                let (selector, body) = rule.split_at(brace);
                out.push_str(scope);
                out.push(' ');
                out.push_str(selector.trim());
                out.push(' ');
                out.push_str(body);
            }
            None => out.push_str(rule),
        }
        out.push('\n');
    }
    out
}

/// Deserializing syntect's default syntaxes is expensive; load once and reuse
/// across every render (each file open and live-reload).
fn syntax_set() -> &'static SyntaxSet {
    static SYNTAX_SET: OnceLock<SyntaxSet> = OnceLock::new();
    SYNTAX_SET.get_or_init(SyntaxSet::load_defaults_newlines)
}

struct ClassHighlighter {
    syntax_set: &'static SyntaxSet,
}

impl ClassHighlighter {
    fn new() -> Self {
        Self {
            syntax_set: syntax_set(),
        }
    }

    fn find_syntax(&self, token: &str) -> &SyntaxReference {
        let token = token.trim();
        self.syntax_set
            .find_syntax_by_token(token)
            .or_else(|| self.syntax_set.find_syntax_by_extension(token))
            .or_else(|| self.syntax_set.find_syntax_by_name(token))
            .or_else(|| {
                self.syntax_set
                    .syntaxes()
                    .iter()
                    .find(|s| s.name.eq_ignore_ascii_case(token))
            })
            .unwrap_or_else(|| self.syntax_set.find_syntax_plain_text())
    }
}

impl SyntaxHighlighterAdapter for ClassHighlighter {
    fn write_highlighted(
        &self,
        output: &mut dyn Write,
        lang: Option<&str>,
        code: &str,
    ) -> io::Result<()> {
        let token = lang
            .map(|l| l.split_whitespace().next().unwrap_or(l))
            .unwrap_or("");
        let syntax = self.find_syntax(token);
        let mut generator =
            ClassedHTMLGenerator::new_with_class_style(syntax, self.syntax_set, CLASS_STYLE);
        for line in LinesWithEndings::from(code) {
            generator
                .parse_html_for_line_which_includes_newline(line)
                .map_err(|e| io::Error::new(io::ErrorKind::Other, e.to_string()))?;
        }
        output.write_all(generator.finalize().as_bytes())
    }

    fn write_pre_tag(
        &self,
        output: &mut dyn Write,
        attributes: HashMap<String, String>,
    ) -> io::Result<()> {
        write_tag(output, "pre", attributes)
    }

    fn write_code_tag(
        &self,
        output: &mut dyn Write,
        attributes: HashMap<String, String>,
    ) -> io::Result<()> {
        write_tag(output, "code", attributes)
    }
}

fn write_tag(output: &mut dyn Write, tag: &str, attributes: HashMap<String, String>) -> io::Result<()> {
    write!(output, "<{tag}")?;
    let mut attrs: Vec<_> = attributes.into_iter().collect();
    attrs.sort();
    for (key, value) in attrs {
        write!(output, " {key}=\"")?;
        comrak::html::escape(output, value.as_bytes())?; // attrs (e.g. fence lang) are untrusted
        output.write_all(b"\"")?;
    }
    write!(output, ">")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn toc_ids_match_rendered_heading_ids() {
        let doc = render("# Hello World\n\ntext\n\n## Section *Two*\n", "x.md");
        assert_eq!(doc.toc.len(), 2);
        assert_eq!(doc.toc[0].text, "Hello World");
        assert_eq!(doc.toc[0].level, 1);
        assert_eq!(doc.toc[1].text, "Section Two");
        for entry in &doc.toc {
            assert!(
                doc.html.contains(&format!("id=\"{}\"", entry.id)),
                "id {:?} not found in html:\n{}",
                entry.id,
                doc.html
            );
        }
    }

    #[test]
    fn duplicate_headings_get_unique_ids() {
        let doc = render("# Dup\n\n# Dup\n", "x.md");
        assert_eq!(doc.toc[0].id, "dup");
        assert_eq!(doc.toc[1].id, "dup-1");
        assert!(doc.html.contains("id=\"dup-1\""));
    }

    #[test]
    fn raw_html_is_escaped() {
        let doc = render("<script>alert(1)</script>\n", "x.md");
        assert!(!doc.html.contains("<script>"), "html: {}", doc.html);
    }

    #[test]
    fn gfm_table_tasklist_strikethrough() {
        let doc = render(
            "| a | b |\n|---|---|\n| 1 | 2 |\n\n- [x] done\n- [ ] todo\n\n~~gone~~\n",
            "x.md",
        );
        assert!(doc.html.contains("<table>"));
        assert!(doc.html.contains("type=\"checkbox\""));
        assert!(doc.html.contains("<del>"));
    }

    #[test]
    fn fenced_code_is_class_highlighted() {
        let doc = render("```rust\nfn main() {}\n```\n", "x.md");
        assert!(doc.html.contains("hl-"), "html: {}", doc.html);
    }

    #[test]
    fn fence_lang_attribute_is_escaped() {
        let doc = render("```\"><img/src=x/onerror=alert(1)>\ncode\n```\n", "x.md");
        assert!(!doc.html.contains("<img"), "html: {}", doc.html);
        assert!(doc.html.contains("language-&quot;&gt;"), "html: {}", doc.html);
    }

    #[test]
    fn highlight_css_is_scoped_per_theme() {
        let css = highlight_css();
        assert!(css.contains(".hl-"));
        assert!(css.contains(":root "));
        assert!(css.contains("[data-theme=\"dark\"] "));
    }
}
