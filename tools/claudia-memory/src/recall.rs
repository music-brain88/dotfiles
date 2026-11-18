//! 読み出し。記憶のファイルを、版の印と、そこから辿れる記憶の一覧を付けて返す。
//! Recall. Returns a memory file with its version stamp and the memories reachable from it.

use sha2::{Digest, Sha256};

use crate::store::{RelPath, Store, StoreError};

/// 会話の最初に読む 2 つの索引。人格の索引と、配線していない場所の「家」の索引。
/// The two indexes read at the start of a conversation: the persona index and the "home" index.
pub const CORE_INDEX: &str = "core/MEMORY.md";
pub const HOME_INDEX: &str = "home/MEMORY.md";

/// 1 つの記憶を読んだ結果。 / One recalled memory.
#[derive(Debug)]
pub struct Recalled {
  pub path: RelPath,
  pub body: String,
  /// 中身のハッシュ。あとで記憶を直すときに、読んだ版と同じかを確かめるのに使う。
  /// Content hash, used later to check that an edit is based on the version that was read.
  pub version: String,
  /// このファイルから辿れる記憶 (AgentMemory のルートからの相対パス)。
  /// Memories reachable from this file, as paths relative to the AgentMemory root.
  pub links: Vec<RelPath>,
  /// 辿れなかったリンク (AgentMemory の外にあるか、見つからない)。
  /// Links that could not be followed (outside AgentMemory, or not found).
  pub unresolved: Vec<String>,
}

pub fn version_of(body: &str) -> String {
  let digest = Sha256::digest(body.as_bytes());
  let mut out = String::from("sha256:");
  for byte in digest {
    out.push_str(&format!("{byte:02x}"));
  }
  out
}

/// 1 つの記憶を読む。 / Reads one memory.
pub fn recall(store: &dyn Store, path: &RelPath) -> Result<Recalled, StoreError> {
  let body = store.read(path)?;
  let (links, unresolved) = resolve_links(store, path, &body);
  Ok(Recalled {
    path: path.clone(),
    version: version_of(&body),
    body,
    links,
    unresolved,
  })
}

/// 引数なしの読み出し。人格の索引と「家」の索引を返す。「家」が無い保存先では、人格の索引だけを返す。
/// The no-argument recall: the persona index and the home index (only the former when there is no home).
pub fn recall_start(store: &dyn Store) -> Result<Vec<Recalled>, StoreError> {
  let mut out = vec![recall(store, &RelPath::parse(CORE_INDEX)?)?];
  let home = RelPath::parse(HOME_INDEX)?;
  if store.exists(&home) {
    out.push(recall(store, &home)?);
  }
  Ok(out)
}

/// 本文の Markdown リンクと wikilink を拾い、AgentMemory の中のファイルに解決する。
/// Collects Markdown links and wikilinks from the body and resolves them to files inside AgentMemory.
fn resolve_links(store: &dyn Store, from: &RelPath, body: &str) -> (Vec<RelPath>, Vec<String>) {
  let mut links: Vec<RelPath> = Vec::new();
  let mut unresolved: Vec<String> = Vec::new();
  let mut push_link = |p: RelPath| {
    if &p != from && !links.contains(&p) {
      links.push(p);
    }
  };

  for target in markdown_link_targets(body) {
    match RelPath::resolve(from.dir(), &target) {
      Ok(p) if store.exists(&p) => push_link(p),
      _ => {
        if !unresolved.contains(&target) {
          unresolved.push(target);
        }
      }
    }
  }
  for name in wikilink_names(body) {
    match store
      .find_by_file_name(&format!("{name}.md"))
      .into_iter()
      .next()
    {
      Some(p) => push_link(p),
      None => {
        let shown = format!("[[{name}]]");
        if !unresolved.contains(&shown) {
          unresolved.push(shown);
        }
      }
    }
  }
  (links, unresolved)
}

/// `[題](target.md)` の target を拾う。URL と、.md で終わらないものは対象にしない。
/// Picks `target` out of `[title](target.md)`; URLs and non-.md targets are ignored.
fn markdown_link_targets(body: &str) -> Vec<String> {
  let mut out = Vec::new();
  let mut rest = body;
  while let Some(start) = rest.find("](") {
    let after = &rest[start + 2..];
    let Some(end) = after.find(')') else { break };
    let raw = after[..end].trim();
    rest = &after[end + 1..];
    let target = raw.split('#').next().unwrap_or("").trim();
    if target.is_empty()
      || target.contains("://")
      || target.starts_with("mailto:")
      || !target.ends_with(".md")
    {
      continue;
    }
    out.push(target.to_string());
  }
  out
}

/// `[[名前]]`・`[[名前|別名]]`・`[[名前#見出し]]` の名前を拾う。フォルダ付きなら最後の部分を使う。
/// Picks the name out of `[[name]]`, `[[name|alias]]`, `[[name#heading]]`; a foldered name keeps its last part.
fn wikilink_names(body: &str) -> Vec<String> {
  let mut out = Vec::new();
  let mut rest = body;
  while let Some(start) = rest.find("[[") {
    let after = &rest[start + 2..];
    let Some(end) = after.find("]]") else { break };
    let inner = &after[..end];
    rest = &after[end + 2..];
    if inner.contains('\n') {
      continue;
    }
    let name = inner.split(['|', '#']).next().unwrap_or("").trim();
    let name = name.rsplit('/').next().unwrap_or("").trim();
    let name = name.strip_suffix(".md").unwrap_or(name);
    if !name.is_empty() && !out.iter().any(|n| n == name) {
      out.push(name.to_string());
    }
  }
  out
}

/// 読んだ結果を、モデルに渡す 1 枚のテキストにする。
/// Renders recalled memories into the single text handed to the model.
pub fn render(items: &[Recalled]) -> String {
  let mut out = String::new();
  for item in items {
    out.push_str(&format!("===== {} =====\n", item.path));
    out.push_str(&format!("version: {}\n\n", item.version));
    out.push_str(item.body.trim_end());
    out.push_str("\n\n");
    if !item.links.is_empty() {
      out.push_str("--- ここから辿れる記憶 (claudia_memory_recall の path にそのまま渡せる) ---\n");
      for link in &item.links {
        out.push_str(&format!("- {link}\n"));
      }
    }
    if !item.unresolved.is_empty() {
      out.push_str("--- 辿れないリンク (AgentMemory の外にあるか、見つからない) ---\n");
      for link in &item.unresolved {
        out.push_str(&format!("- {link}\n"));
      }
    }
    out.push('\n');
  }
  out
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn markdown_targets_skip_urls_and_anchors() {
    let body = "[a](self-model.md) [b](https://example.com/x.md) [c](../core/MEMORY.md#top) [d](image.png) [e](#local)";
    assert_eq!(
      markdown_link_targets(body),
      vec!["self-model.md", "../core/MEMORY.md"]
    );
  }

  #[test]
  fn wikilink_names_drop_alias_heading_and_folder() {
    let body = "[[values]] [[decision-principles|原則]] [[self-model#名]] [[Zettelkasten/ResearchNotes/Note-1]] [[values]]";
    assert_eq!(
      wikilink_names(body),
      vec!["values", "decision-principles", "self-model", "Note-1"]
    );
  }

  #[test]
  fn version_is_a_stable_sha256() {
    assert_eq!(
      version_of(""),
      "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    );
  }
}
