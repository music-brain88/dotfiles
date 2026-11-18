//! 保存先。AgentMemory のルートの下だけを、Markdown だけ、読ませる。
//! Storage. Serves Markdown files, and only those under the AgentMemory root.

use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

/// 1 ファイルの上限。索引と記憶は数 KB〜数十 KB なので、これを超えるものは読ませない。
/// Per-file cap. Indexes and memories are a few KB to tens of KB; anything larger is refused.
pub const MAX_FILE_BYTES: u64 = 512 * 1024;

/// ファイル名で探すときに下りる深さの上限。
/// How deep the file-name search descends.
const MAX_WALK_DEPTH: usize = 6;

#[derive(Debug, PartialEq, Eq)]
pub enum StoreError {
  /// パスの形が受け付けられない (ルートの外に出る、Markdown でない、など)。
  /// The path is not acceptable (escapes the root, is not Markdown, ...).
  BadPath(String),
  /// ファイルが無い。 / No such file.
  NotFound(String),
  /// ルートの外を指している (シンボリックリンクを含む)。 / Resolves outside the root (symlinks included).
  OutsideRoot(String),
  /// 大きすぎる。 / Too large.
  TooLarge(String),
  /// 読めなかった。 / Could not be read.
  Io(String),
}

impl fmt::Display for StoreError {
  fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    match self {
      StoreError::BadPath(m) => write!(f, "パスを受け付けられない: {m}"),
      StoreError::NotFound(p) => write!(f, "ファイルが無い: {p}"),
      StoreError::OutsideRoot(p) => write!(f, "AgentMemory の外を指している: {p}"),
      StoreError::TooLarge(p) => write!(f, "ファイルが大きすぎる: {p}"),
      StoreError::Io(m) => write!(f, "読めなかった: {m}"),
    }
  }
}

/// AgentMemory のルートからの相対パス。正規化済みで、ルートの外に出ない。
/// A path relative to the AgentMemory root: normalized, and never escaping the root.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct RelPath(String);

impl RelPath {
  /// 呼び出し側が渡した文字列を検査して正規化する。
  /// Validates and normalizes a caller-supplied string.
  pub fn parse(raw: &str) -> Result<RelPath, StoreError> {
    Self::resolve("", raw)
  }

  /// `base_dir` (ルートからの相対のフォルダ) を起点に、`link` を解決する。
  /// Resolves `link` against `base_dir` (a folder relative to the root).
  pub fn resolve(base_dir: &str, link: &str) -> Result<RelPath, StoreError> {
    let link = link.trim();
    if link.is_empty() {
      return Err(StoreError::BadPath("空のパス".into()));
    }
    if link.starts_with('/') || link.contains('\\') || link.contains('\0') {
      return Err(StoreError::BadPath(format!(
        "絶対パスや \\ は使えない: {link}"
      )));
    }
    let mut parts: Vec<&str> = base_dir.split('/').filter(|p| !p.is_empty()).collect();
    for part in link.split('/') {
      match part {
        "" | "." => {}
        ".." => {
          if parts.pop().is_none() {
            return Err(StoreError::BadPath(format!(
              "AgentMemory の外に出る: {link}"
            )));
          }
        }
        p if p.starts_with('.') => {
          return Err(StoreError::BadPath(format!(
            "隠しファイルは読めない: {link}"
          )));
        }
        p => parts.push(p),
      }
    }
    let joined = parts.join("/");
    if !joined.ends_with(".md") {
      return Err(StoreError::BadPath(format!("読めるのは .md だけ: {link}")));
    }
    Ok(RelPath(joined))
  }

  pub fn as_str(&self) -> &str {
    &self.0
  }

  /// このファイルのあるフォルダ (ルートからの相対)。ルート直下なら空文字。
  /// The folder holding this file, relative to the root; empty at the top level.
  pub fn dir(&self) -> &str {
    match self.0.rfind('/') {
      Some(i) => &self.0[..i],
      None => "",
    }
  }
}

impl fmt::Display for RelPath {
  fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    f.write_str(&self.0)
  }
}

/// 保存先の口。手元のフォルダのほかに、あとで別の保存先を足せるようにしてある。
/// The storage interface, so another backend can be added beside the local folder.
pub trait Store {
  fn read(&self, path: &RelPath) -> Result<String, StoreError>;
  fn exists(&self, path: &RelPath) -> bool;
  /// ファイル名が一致する Markdown を、ルートの下から探す。結果は並びが安定している。
  /// Finds Markdown files by file name under the root, in a stable order.
  fn find_by_file_name(&self, file_name: &str) -> Vec<RelPath>;
}

/// 手元のフォルダを保存先にする。 / A store backed by a local folder.
pub struct FsStore {
  root: PathBuf,
}

impl FsStore {
  /// `root` は実在するフォルダでなければならない。 / `root` must be an existing folder.
  pub fn open(root: &Path) -> Result<FsStore, StoreError> {
    let canonical =
      fs::canonicalize(root).map_err(|e| StoreError::Io(format!("{}: {e}", root.display())))?;
    if !canonical.is_dir() {
      return Err(StoreError::Io(format!(
        "フォルダではない: {}",
        root.display()
      )));
    }
    Ok(FsStore { root: canonical })
  }

  /// 実体のパスに直し、シンボリックリンクを辿った先がルートの下にあることを確かめる。
  /// Resolves to the real path and checks it still lies under the root after following symlinks.
  fn real_path(&self, path: &RelPath) -> Result<PathBuf, StoreError> {
    let joined = self.root.join(path.as_str());
    let real = fs::canonicalize(&joined).map_err(|_| StoreError::NotFound(path.to_string()))?;
    if !real.starts_with(&self.root) {
      return Err(StoreError::OutsideRoot(path.to_string()));
    }
    Ok(real)
  }

  fn walk(&self, dir: &Path, depth: usize, file_name: &str, found: &mut Vec<RelPath>) {
    if depth > MAX_WALK_DEPTH {
      return;
    }
    let Ok(entries) = fs::read_dir(dir) else {
      return;
    };
    let mut entries: Vec<_> = entries.flatten().collect();
    entries.sort_by_key(|e| e.file_name());
    for entry in entries {
      let name = entry.file_name();
      let Some(name) = name.to_str() else { continue };
      if name.starts_with('.') {
        continue;
      }
      // シンボリックリンクは辿らない。ルートの外へ出る道にも、循環にもなるため。
      // Never follow symlinks: they can lead outside the root, or loop.
      let Ok(kind) = entry.file_type() else {
        continue;
      };
      if kind.is_dir() {
        self.walk(&entry.path(), depth + 1, file_name, found);
      } else if kind.is_file() && name == file_name {
        if let Ok(rel) = entry.path().strip_prefix(&self.root) {
          if let Some(rel) = rel.to_str() {
            if let Ok(parsed) = RelPath::parse(rel) {
              found.push(parsed);
            }
          }
        }
      }
    }
  }
}

impl Store for FsStore {
  fn read(&self, path: &RelPath) -> Result<String, StoreError> {
    let real = self.real_path(path)?;
    let meta = fs::metadata(&real).map_err(|e| StoreError::Io(format!("{path}: {e}")))?;
    if !meta.is_file() {
      return Err(StoreError::NotFound(path.to_string()));
    }
    if meta.len() > MAX_FILE_BYTES {
      return Err(StoreError::TooLarge(path.to_string()));
    }
    fs::read_to_string(&real).map_err(|e| StoreError::Io(format!("{path}: {e}")))
  }

  fn exists(&self, path: &RelPath) -> bool {
    self.real_path(path).map(|p| p.is_file()).unwrap_or(false)
  }

  fn find_by_file_name(&self, file_name: &str) -> Vec<RelPath> {
    let mut found = Vec::new();
    if file_name.contains('/') || file_name.starts_with('.') || !file_name.ends_with(".md") {
      return found;
    }
    self.walk(&self.root, 0, file_name, &mut found);
    // 人格の憲法 (core/) を先頭にする。同じ名前が複数あるときに、core を優先して辿らせるため。
    // Put core/ first so that it wins when several files share a name.
    found.sort_by_key(|p| (!p.as_str().starts_with("core/"), p.as_str().to_string()));
    found
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn parse_accepts_plain_relative_markdown() {
    assert_eq!(
      RelPath::parse("core/self-model.md").unwrap().as_str(),
      "core/self-model.md"
    );
    assert_eq!(
      RelPath::parse("./core//MEMORY.md").unwrap().as_str(),
      "core/MEMORY.md"
    );
  }

  #[test]
  fn parse_rejects_escapes_and_non_markdown() {
    for bad in [
      "",
      "/etc/passwd",
      "../x.md",
      "core/../../x.md",
      "core\\x.md",
      "core/x.txt",
      ".git/config.md",
      "core/.hidden.md",
    ] {
      assert!(RelPath::parse(bad).is_err(), "should reject {bad:?}");
    }
  }

  #[test]
  fn resolve_follows_links_relative_to_the_file() {
    let from = RelPath::parse("obsidian/MEMORY.md").unwrap();
    assert_eq!(
      RelPath::resolve(from.dir(), "../core/MEMORY.md")
        .unwrap()
        .as_str(),
      "core/MEMORY.md"
    );
    assert_eq!(
      RelPath::resolve(from.dir(), "index/project.md")
        .unwrap()
        .as_str(),
      "obsidian/index/project.md"
    );
    assert!(RelPath::resolve(from.dir(), "../../outside.md").is_err());
  }

  #[test]
  fn dir_of_top_level_file_is_empty() {
    assert_eq!(RelPath::parse("MEMORY.md").unwrap().dir(), "");
  }
}
