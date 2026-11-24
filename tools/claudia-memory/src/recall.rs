//! 読み出し。記憶のファイルを、版の印と、そこから辿れる記憶の一覧を付けて返す。
//! Recall. Returns a memory file with its version stamp and the memories reachable from it.

use std::collections::HashMap;

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

/// ファイル名から記憶を引く索引。保存先を歩くのは、最初に引いたときの 1 回だけにする。
/// wikilink が 1 つも無い読み出しでは、1 回も歩かない。
/// An index from file name to memories. The storage is walked once, on the first lookup,
/// and not at all when a recall meets no wikilink.
struct NameIndex<'a> {
  store: &'a dyn Store,
  by_name: Option<HashMap<String, Vec<RelPath>>>,
}

impl<'a> NameIndex<'a> {
  fn new(store: &'a dyn Store) -> NameIndex<'a> {
    NameIndex {
      store,
      by_name: None,
    }
  }

  fn lookup(&mut self, file_name: &str) -> &[RelPath] {
    let store = self.store;
    let by_name = self.by_name.get_or_insert_with(|| {
      let mut map: HashMap<String, Vec<RelPath>> = HashMap::new();
      for path in store.markdown_files() {
        let name = path.as_str().rsplit('/').next().unwrap_or("").to_string();
        map.entry(name).or_default().push(path);
      }
      map
    });
    by_name.get(file_name).map(Vec::as_slice).unwrap_or(&[])
  }
}

/// 1 つの記憶を読む。 / Reads one memory.
pub fn recall(store: &dyn Store, path: &RelPath) -> Result<Recalled, StoreError> {
  recall_with(store, &mut NameIndex::new(store), path)
}

fn recall_with(
  store: &dyn Store,
  index: &mut NameIndex,
  path: &RelPath,
) -> Result<Recalled, StoreError> {
  let body = store.read(path)?;
  let (links, unresolved) = resolve_links(store, index, path, &body);
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
  let mut index = NameIndex::new(store);
  let mut out = vec![recall_with(
    store,
    &mut index,
    &RelPath::parse(CORE_INDEX)?,
  )?];
  let home = RelPath::parse(HOME_INDEX)?;
  if store.exists(&home) {
    out.push(recall_with(store, &mut index, &home)?);
  }
  Ok(out)
}

/// 本文の Markdown リンクと wikilink を拾い、AgentMemory の中のファイルに解決する。
/// Collects Markdown links and wikilinks from the body and resolves them to files inside AgentMemory.
fn resolve_links(
  store: &dyn Store,
  index: &mut NameIndex,
  from: &RelPath,
  body: &str,
) -> (Vec<RelPath>, Vec<String>) {
  let mut links: Vec<RelPath> = Vec::new();
  let mut unresolved: Vec<String> = Vec::new();

  for target in markdown_link_targets(body) {
    match RelPath::resolve(from.dir(), &target) {
      Ok(p) if store.exists(&p) => push_unique(&mut links, from, p),
      _ => {
        if !unresolved.contains(&target) {
          unresolved.push(target);
        }
      }
    }
  }
  for target in wikilink_targets(body) {
    match resolve_wikilink(store, index, from, &target) {
      Some(p) => push_unique(&mut links, from, p),
      None => {
        let shown = format!("[[{target}]]");
        if !unresolved.contains(&shown) {
          unresolved.push(shown);
        }
      }
    }
  }
  (links, unresolved)
}

fn push_unique(links: &mut Vec<RelPath>, from: &RelPath, path: RelPath) {
  if &path != from && !links.contains(&path) {
    links.push(path);
  }
}

/// vault のルートから書いた wikilink の先頭に付く、AgentMemory のフォルダ名。
/// The AgentMemory folder name that leads a wikilink written from the vault root.
const VAULT_PREFIX: &str = "AgentMemory/";

/// wikilink 1 つを解決する。
/// フォルダ付きの wikilink (`[[core/values]]`、`[[AgentMemory/home/MEMORY]]`) は、パスとして解決し、
/// 見つからなければ辿れないリンクにする。名前だけの検索には落とさない。落とすと、AgentMemory の外の
/// ノートを指す wikilink が、同じ名前の中のファイルに化けるためである。
/// 名前だけの wikilink (`[[values]]`) は、ファイル名で探す。同じ名前が複数あるときは、
/// 同じフォルダのファイル、core/ のファイル、パスの順で先のもの、の順に選ぶ。
/// Resolves one wikilink.
/// A qualified wikilink is resolved as a path and left unresolved when missing; it never falls back
/// to a basename lookup, which would turn a link to a note outside AgentMemory into an in-root namesake.
/// An unqualified wikilink is looked up by file name, preferring the same folder, then core/, then path order.
fn resolve_wikilink(
  store: &dyn Store,
  index: &mut NameIndex,
  from: &RelPath,
  target: &str,
) -> Option<RelPath> {
  if target.contains('/') {
    let inside = target.strip_prefix(VAULT_PREFIX).unwrap_or(target);
    let path = RelPath::parse(&format!("{inside}.md")).ok()?;
    return store.exists(&path).then_some(path);
  }
  let matches = index.lookup(&format!("{target}.md"));
  matches
    .iter()
    .find(|p| p.dir() == from.dir())
    .or_else(|| matches.first())
    .cloned()
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

/// `[[先]]`・`[[先|別名]]`・`[[先#見出し]]` の先を拾う。フォルダが付いていれば、付けたまま返す。
/// Picks the target out of `[[target]]`, `[[target|alias]]`, `[[target#heading]]`, keeping any folder part.
fn wikilink_targets(body: &str) -> Vec<String> {
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
    let target = inner.split(['|', '#']).next().unwrap_or("").trim();
    let target = target
      .strip_suffix(".md")
      .unwrap_or(target)
      .trim_matches('/');
    if !target.is_empty() && !out.iter().any(|t| t == target) {
      out.push(target.to_string());
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
  fn wikilink_targets_drop_alias_and_heading_but_keep_the_folder() {
    let body = "[[values]] [[decision-principles|原則]] [[self-model#名]] [[Zettelkasten/ResearchNotes/Note-1]] [[values]]";
    assert_eq!(
      wikilink_targets(body),
      vec![
        "values",
        "decision-principles",
        "self-model",
        "Zettelkasten/ResearchNotes/Note-1"
      ]
    );
  }

  /// 保存先を歩いた回数を数える、メモリ上の保存先。
  /// An in-memory store that counts how often the storage is walked.
  struct CountingStore {
    files: Vec<(&'static str, &'static str)>,
    walks: std::cell::Cell<usize>,
  }

  impl Store for CountingStore {
    fn read(&self, path: &RelPath) -> Result<String, StoreError> {
      self
        .files
        .iter()
        .find(|(p, _)| *p == path.as_str())
        .map(|(_, body)| body.to_string())
        .ok_or_else(|| StoreError::NotFound(path.to_string()))
    }
    fn exists(&self, path: &RelPath) -> bool {
      self.files.iter().any(|(p, _)| *p == path.as_str())
    }
    fn markdown_files(&self) -> Vec<RelPath> {
      self.walks.set(self.walks.get() + 1);
      self
        .files
        .iter()
        .map(|(p, _)| RelPath::parse(p).unwrap())
        .collect()
    }
  }

  fn counting_store() -> CountingStore {
    CountingStore {
      files: vec![
        ("core/MEMORY.md", "[[values]] [[self-model]] [[missing-1]] [[missing-2]] [[missing-3]]"),
        ("core/self-model.md", "[plain](values.md)"),
        ("core/values.md", "誠実さ"),
        ("home/MEMORY.md", "[[values]] [[MEMORY]] [[AgentMemory/core/MEMORY]] [[Zettelkasten/ResearchNotes/values]] [[core/self-model]]"),
      ],
      walks: std::cell::Cell::new(0),
    }
  }

  #[test]
  fn the_storage_is_walked_once_per_recall_however_many_wikilinks_there_are() {
    let store = counting_store();
    let items = recall_start(&store).unwrap();
    assert_eq!(items.len(), 2);
    assert_eq!(store.walks.get(), 1);
  }

  #[test]
  fn a_recall_without_wikilinks_never_walks_the_storage() {
    let store = counting_store();
    recall(&store, &RelPath::parse("core/self-model.md").unwrap()).unwrap();
    assert_eq!(store.walks.get(), 0);
  }

  #[test]
  fn qualified_wikilinks_resolve_as_paths_and_never_fall_back_to_a_namesake() {
    let store = counting_store();
    let home = recall(&store, &RelPath::parse("home/MEMORY.md").unwrap()).unwrap();
    let links: Vec<&str> = home.links.iter().map(RelPath::as_str).collect();
    // [[AgentMemory/core/MEMORY]] は core/MEMORY.md に、[[core/self-model]] は core/self-model.md に解決される。
    // [[MEMORY]] は同じフォルダの home/MEMORY.md (自分自身) なので、一覧には出ない。
    assert_eq!(
      links,
      vec!["core/values.md", "core/MEMORY.md", "core/self-model.md"]
    );
    // AgentMemory の外を指す wikilink は、同じ名前の core/values.md に化けない。
    assert_eq!(
      home.unresolved,
      vec!["[[Zettelkasten/ResearchNotes/values]]"]
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
