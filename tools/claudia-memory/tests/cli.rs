//! バイナリを実際に起動して、標準入出力で MCP を話す通しのテスト。
//! End-to-end tests: spawn the real binary and speak MCP over stdio.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

use serde_json::{json, Value};

static COUNTER: AtomicUsize = AtomicUsize::new(0);

/// テストごとに、小さな AgentMemory を一時フォルダに作る。
/// Builds a small AgentMemory tree in a fresh temp folder for each test.
struct Fixture {
  base: PathBuf,
}

impl Fixture {
  fn new() -> Fixture {
    let n = COUNTER.fetch_add(1, Ordering::SeqCst);
    let base = std::env::temp_dir().join(format!("claudia-memory-test-{}-{n}", std::process::id()));
    let _ = fs::remove_dir_all(&base);
    let fx = Fixture { base };
    fx.write("AgentMemory/core/MEMORY.md", "# Core\n\n- [Self model](self-model.md) — 私は誰か\n- [Sessions](../sessions/INDEX.md)\n- [外](https://example.com/x.md)\n");
    fx.write(
      "AgentMemory/core/self-model.md",
      "私はクラウディア。[[values]] と [[MOC-ObsidianWorkflow]] を見る。\n",
    );
    fx.write("AgentMemory/core/values.md", "誠実さ。\n");
    fx.write(
      "AgentMemory/home/MEMORY.md",
      "- [Core index](../core/MEMORY.md)\n- [sudo](sudo.md)\n",
    );
    fx.write("AgentMemory/home/sudo.md", "sudo は別ターミナルで。\n");
    fx.write("AgentMemory/sessions/INDEX.md", "# Sessions\n");
    fx.write("AgentMemory/core/notes.txt", "Markdown ではない\n");
    fx.write("outside.md", "SECRET-OUTSIDE\n");
    fx
  }

  fn write(&self, rel: &str, body: &str) {
    let path = self.base.join(rel);
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    fs::write(path, body).unwrap();
  }

  fn root(&self) -> PathBuf {
    self.base.join("AgentMemory")
  }
}

impl Drop for Fixture {
  fn drop(&mut self) {
    let _ = fs::remove_dir_all(&self.base);
  }
}

/// メッセージを順に送り、返ってきた行を JSON として集める。
/// Sends the messages in order and collects the reply lines as JSON.
fn talk(root: &Path, messages: &[Value]) -> Vec<Value> {
  let mut child = Command::new(env!("CARGO_BIN_EXE_claudia-memory"))
    .arg("--root")
    .arg(root)
    .stdin(Stdio::piped())
    .stdout(Stdio::piped())
    .stderr(Stdio::piped())
    .spawn()
    .unwrap();
  {
    let stdin = child.stdin.as_mut().unwrap();
    for message in messages {
      writeln!(stdin, "{message}").unwrap();
    }
  }
  let output = child.wait_with_output().unwrap();
  assert!(
    output.status.success(),
    "stderr: {}",
    String::from_utf8_lossy(&output.stderr)
  );
  String::from_utf8(output.stdout)
    .unwrap()
    .lines()
    .map(|l| serde_json::from_str(l).unwrap())
    .collect()
}

fn call(id: u64, arguments: Value) -> Value {
  json!({ "jsonrpc": "2.0", "id": id, "method": "tools/call", "params": { "name": "claudia_memory_recall", "arguments": arguments } })
}

fn text_of(reply: &Value) -> &str {
  reply["result"]["content"][0]["text"].as_str().unwrap()
}

fn is_error(reply: &Value) -> bool {
  reply["result"]["isError"].as_bool().unwrap()
}

#[test]
fn initialize_and_list_expose_the_recall_tool() {
  let fx = Fixture::new();
  let replies = talk(
    &fx.root(),
    &[
      json!({ "jsonrpc": "2.0", "id": 0, "method": "initialize", "params": { "protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": { "name": "t", "version": "0" } } }),
      json!({ "jsonrpc": "2.0", "method": "notifications/initialized" }),
      json!({ "jsonrpc": "2.0", "id": 1, "method": "tools/list" }),
    ],
  );
  // 通知には返事をしないので、返事は 2 つ。 / Notifications get no reply, so there are two.
  assert_eq!(replies.len(), 2);
  assert_eq!(replies[0]["result"]["protocolVersion"], "2025-11-25");
  assert_eq!(replies[0]["result"]["serverInfo"]["name"], "claudia-memory");
  let tools = replies[1]["result"]["tools"].as_array().unwrap();
  assert_eq!(tools.len(), 1);
  assert_eq!(tools[0]["name"], "claudia_memory_recall");
}

#[test]
fn recall_without_arguments_returns_core_and_home_indexes() {
  let fx = Fixture::new();
  let replies = talk(&fx.root(), &[call(1, json!({}))]);
  assert!(!is_error(&replies[0]));
  let text = text_of(&replies[0]);
  assert!(text.contains("===== core/MEMORY.md ====="));
  assert!(text.contains("===== home/MEMORY.md ====="));
  assert!(text.contains("私は誰か"));
  // リンクは、AgentMemory のルートからのパスに直って返る。 / Links come back as root-relative paths.
  assert!(text.contains("- core/self-model.md\n"));
  assert!(text.contains("- sessions/INDEX.md\n"));
  assert!(text.contains("- home/sudo.md\n"));
  // URL は辿れる記憶に入らない。 / URLs are not listed as reachable memories.
  assert!(!text.contains("example.com/x.md\n- "));
}

#[test]
fn recall_without_home_returns_only_core() {
  let fx = Fixture::new();
  fs::remove_dir_all(fx.root().join("home")).unwrap();
  let replies = talk(&fx.root(), &[call(1, json!({}))]);
  assert!(!is_error(&replies[0]));
  assert!(text_of(&replies[0]).contains("===== core/MEMORY.md ====="));
  assert!(!text_of(&replies[0]).contains("home/MEMORY.md ====="));
}

#[test]
fn recall_by_path_returns_body_version_and_resolved_wikilinks() {
  let fx = Fixture::new();
  let replies = talk(
    &fx.root(),
    &[call(1, json!({ "path": "core/self-model.md" }))],
  );
  assert!(!is_error(&replies[0]));
  let text = text_of(&replies[0]);
  assert!(text.contains("私はクラウディア"));
  let version = text
    .lines()
    .find(|l| l.starts_with("version: sha256:"))
    .unwrap();
  assert_eq!(version.len(), "version: sha256:".len() + 64);
  assert!(text.contains("- core/values.md\n"));
  // AgentMemory の外のノートへの wikilink は、辿れないリンクとして出る。
  // A wikilink to a note outside AgentMemory is reported as unresolved.
  assert!(text.contains("- [[MOC-ObsidianWorkflow]]\n"));
}

#[test]
fn paths_outside_the_root_are_refused() {
  let fx = Fixture::new();
  let outside = fx.base.join("outside.md");
  let attempts = [
    "../outside.md",
    "core/../../outside.md",
    outside.to_str().unwrap(),
    "core/notes.txt",
    "core/.hidden.md",
    "core/missing.md",
  ];
  let messages: Vec<Value> = attempts
    .iter()
    .enumerate()
    .map(|(i, p)| call(i as u64, json!({ "path": p })))
    .collect();
  let replies = talk(&fx.root(), &messages);
  assert_eq!(replies.len(), attempts.len());
  for (reply, attempt) in replies.iter().zip(attempts) {
    assert!(is_error(reply), "should refuse {attempt}");
    assert!(
      !text_of(reply).contains("SECRET-OUTSIDE"),
      "leaked through {attempt}"
    );
  }
}

#[cfg(unix)]
#[test]
fn symlinks_leading_outside_the_root_are_refused() {
  let fx = Fixture::new();
  std::os::unix::fs::symlink(fx.base.join("outside.md"), fx.root().join("core/leak.md")).unwrap();
  let replies = talk(&fx.root(), &[call(1, json!({ "path": "core/leak.md" }))]);
  assert!(is_error(&replies[0]));
  assert!(!text_of(&replies[0]).contains("SECRET-OUTSIDE"));
}

/// ルートの中のリンクでも、辿った先が隠しファイルや .md でないファイルなら読ませない。
/// 規則は、渡されたパスの文字列ではなく、辿り着いた先に当てる。
/// A symlink inside the root must not expose a hidden or non-Markdown file that also lives inside the root:
/// the rules apply to where the path leads, not to the string that was passed.
#[cfg(unix)]
#[test]
fn symlinks_to_forbidden_files_inside_the_root_are_refused() {
  let fx = Fixture::new();
  fx.write("AgentMemory/.secret.md", "SECRET-HIDDEN\n");
  fx.write("AgentMemory/.vault/inner.md", "SECRET-HIDDEN-DIR\n");
  fx.write("AgentMemory/notes.txt", "SECRET-TEXT\n");
  let root = fx.root();
  std::os::unix::fs::symlink(root.join(".secret.md"), root.join("core/alias-hidden.md")).unwrap();
  std::os::unix::fs::symlink(
    root.join(".vault/inner.md"),
    root.join("core/alias-hidden-dir.md"),
  )
  .unwrap();
  std::os::unix::fs::symlink(root.join("notes.txt"), root.join("core/alias-text.md")).unwrap();
  let attempts = [
    "core/alias-hidden.md",
    "core/alias-hidden-dir.md",
    "core/alias-text.md",
  ];
  let messages: Vec<Value> = attempts
    .iter()
    .enumerate()
    .map(|(i, p)| call(i as u64, json!({ "path": p })))
    .collect();
  let replies = talk(&root, &messages);
  for (reply, attempt) in replies.iter().zip(attempts) {
    assert!(is_error(reply), "should refuse {attempt}");
    assert!(
      !text_of(reply).contains("SECRET-"),
      "leaked through {attempt}"
    );
  }
  // 禁じたファイルへのリンクは、索引の「辿れる記憶」にも出さない。
  // Links to forbidden files are not listed as reachable either.
  fx.write(
    "AgentMemory/core/MEMORY.md",
    "- [a](alias-hidden.md)\n- [b](alias-text.md)\n- [ok](self-model.md)\n",
  );
  let replies = talk(&root, &[call(1, json!({}))]);
  let text = text_of(&replies[0]);
  assert!(text.contains("- core/self-model.md\n"));
  assert!(!text.contains("- core/alias-hidden.md\n"));
  assert!(!text.contains("- core/alias-text.md\n"));
}

/// ルートの中の、読んでよい Markdown を指すリンクは、そのまま読める。
/// A symlink to an allowed Markdown file inside the root still works.
#[cfg(unix)]
#[test]
fn symlinks_to_allowed_files_inside_the_root_are_served() {
  let fx = Fixture::new();
  let root = fx.root();
  std::os::unix::fs::symlink(
    root.join("core/values.md"),
    root.join("home/values-alias.md"),
  )
  .unwrap();
  let replies = talk(&root, &[call(1, json!({ "path": "home/values-alias.md" }))]);
  assert!(!is_error(&replies[0]));
  assert!(text_of(&replies[0]).contains("誠実さ"));
}

#[test]
fn protocol_errors_are_reported() {
  let fx = Fixture::new();
  let mut child = Command::new(env!("CARGO_BIN_EXE_claudia-memory"))
    .arg("--root")
    .arg(fx.root())
    .stdin(Stdio::piped())
    .stdout(Stdio::piped())
    .spawn()
    .unwrap();
  {
    let stdin = child.stdin.as_mut().unwrap();
    writeln!(stdin, "not json").unwrap();
    writeln!(
      stdin,
      "{}",
      json!({ "jsonrpc": "2.0", "id": 7, "method": "no/such" })
    )
    .unwrap();
    writeln!(stdin, "{}", json!({ "jsonrpc": "2.0", "id": 8, "method": "tools/call", "params": { "name": "other_tool", "arguments": {} } })).unwrap();
    writeln!(stdin, "{}", call(9, json!({ "path": 3 }))).unwrap();
  }
  let output = child.wait_with_output().unwrap();
  let replies: Vec<Value> = String::from_utf8(output.stdout)
    .unwrap()
    .lines()
    .map(|l| serde_json::from_str(l).unwrap())
    .collect();
  assert_eq!(replies[0]["error"]["code"], -32700);
  assert_eq!(replies[1]["error"]["code"], -32601);
  assert_eq!(replies[2]["error"]["code"], -32602);
  assert!(is_error(&replies[3]));
}

#[test]
fn a_missing_root_fails_at_startup() {
  let status = Command::new(env!("CARGO_BIN_EXE_claudia-memory"))
    .arg("--root")
    .arg("/nonexistent/claudia-memory-root")
    .stdin(Stdio::null())
    .stderr(Stdio::null())
    .status()
    .unwrap();
  assert_eq!(status.code(), Some(1));
}
