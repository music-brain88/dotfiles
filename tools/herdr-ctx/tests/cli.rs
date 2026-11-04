//! CLI の統合テスト。PATH の先に偽の herdr を置き、終了コードと stdout / stderr の約束を確かめる。
//! CLI integration tests. A fake herdr on PATH pins the contract on exit codes and output streams.
//!
//! 偽の herdr はシェルの組み込みコマンドだけを使う。ビルドサンドボックスの PATH に頼らないため。
//! The fake herdr uses shell builtins only, so it does not depend on the build sandbox's PATH.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::thread;
use std::time::{Duration, Instant};

const LIST_JSON: &str = r#"{"id":"cli:agent:list","result":{"agents":[{"agent":"claude","agent_status":"working","cwd":"/home/archie/dotfiles","name":"commander-dotfiles","pane_id":"w3C:p1W"},{"agent":"claude","agent_status":"idle","cwd":"/home/archie/notes","pane_id":"w3T:p2"},{"agent":"copilot","agent_status":"idle","cwd":"/home/archie/tools","pane_id":"w3U:p1"}]}}"#;
const GET_COMMANDER_JSON: &str = r#"{"id":"cli:agent:get","result":{"agent":{"name":"commander-dotfiles","pane_id":"w3C:p1W"},"type":"agent_info"}}"#;
const SERVER_DOWN_JSON: &str = r#"{"id":"cli:agent:list","error":{"code":"server_not_running","message":"no herdr server is running"}}"#;

struct Sandbox {
  root: PathBuf,
}

impl Sandbox {
  fn new(name: &str) -> Self {
    let root = std::env::temp_dir().join(format!("herdr-ctx-cli-{}-{name}", std::process::id()));
    let _ = fs::remove_dir_all(&root);
    fs::create_dir_all(root.join("bin")).unwrap();
    fs::create_dir_all(root.join("home/.herdr/ctx/panes")).unwrap();
    Self { root }
  }

  fn bin(&self) -> PathBuf {
    self.root.join("bin")
  }

  fn home(&self) -> PathBuf {
    self.root.join("home")
  }

  fn log(&self) -> PathBuf {
    self.root.join("herdr.log")
  }

  /// 呼ばれた引数を記録し、サブコマンドごとに固定の JSON を返す偽の herdr を置く。
  /// Installs a fake herdr that logs its arguments and answers each subcommand with fixed JSON.
  fn fake_herdr(&self, list: &str, get: &str, exit_code: i32) {
    let script = format!(
      "#!/bin/sh\necho \"$*\" >> '{log}'\ncase \"$1 $2\" in\n  'agent list') printf '%s\\n' '{list}' ;;\n  'agent get') printf '%s\\n' '{get}' ;;\nesac\nexit {exit_code}\n",
      log = self.log().display(),
    );
    let path = self.bin().join("herdr");
    fs::write(&path, script).unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
  }

  /// updated_at は実行する日に左右されないように、必ず 10 分より古い固定の時刻にする。
  /// updated_at is a fixed time always older than ten minutes, so results do not depend on the date.
  fn sidecar(&self, file: &str, pct: u32) {
    let text = format!(
      r#"{{"pane_id":"w3C:p1W","used_percentage":{pct},"context_window_size":1000000,"total_input_tokens":620000,"model_id":"claude-fable-5-1","model_name":"Fable 5.1","updated_at":"2020-01-01T00:00:00Z"}}"#
    );
    fs::write(self.home().join(".herdr/ctx/panes").join(file), text).unwrap();
  }

  fn command(&self, args: &[&str]) -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_herdr-ctx"));
    command
      .args(args)
      .env("PATH", self.bin())
      .env("HOME", self.home())
      .env_remove("HERDR_PANE_ID");
    command
  }

  fn run(&self, args: &[&str]) -> Output {
    self.command(args).output().expect("binary runs")
  }

  fn run_in_pane(&self, args: &[&str], pane_id: &str) -> Output {
    self
      .command(args)
      .env("HERDR_PANE_ID", pane_id)
      .output()
      .expect("binary runs")
  }
}

fn stdout(output: &Output) -> String {
  String::from_utf8_lossy(&output.stdout).into_owned()
}

fn stderr(output: &Output) -> String {
  String::from_utf8_lossy(&output.stderr).into_owned()
}

fn wait_for(path: &Path) -> bool {
  let deadline = Instant::now() + Duration::from_secs(10);
  while Instant::now() < deadline {
    if path.exists() {
      return true;
    }
    thread::sleep(Duration::from_millis(50));
  }
  false
}

#[test]
fn list_prints_json_lines() {
  let sandbox = Sandbox::new("list");
  sandbox.fake_herdr(LIST_JSON, "", 0);
  sandbox.sidecar("w3C_p1W.json", 62);
  sandbox.sidecar("w3U_p1.json", 70);

  let output = sandbox.run(&["list"]);

  assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
  let text = stdout(&output);
  let lines: Vec<&str> = text.lines().collect();
  assert_eq!(lines.len(), 3);
  let first: serde_json::Value = serde_json::from_str(lines[0]).unwrap();
  assert_eq!(first["pct"], 62);
  assert_eq!(first["model"], "Fable 5.1");
  assert_eq!(first["stale"], true);
  let second: serde_json::Value = serde_json::from_str(lines[1]).unwrap();
  assert_eq!(second["note"], "no sidecar");
  let third: serde_json::Value = serde_json::from_str(lines[2]).unwrap();
  assert!(third["pct"].is_null());
  assert_eq!(third["note"], "not a claude agent");
}

#[test]
fn list_table_has_a_header() {
  let sandbox = Sandbox::new("table");
  sandbox.fake_herdr(LIST_JSON, "", 0);

  let output = sandbox.run(&["list", "--table"]);

  assert_eq!(output.status.code(), Some(0));
  assert!(stdout(&output).starts_with("NAME"), "{}", stdout(&output));
}

#[test]
fn list_without_herdr_fails_with_one_stderr_line() {
  let sandbox = Sandbox::new("no-herdr");

  let output = sandbox.run(&["list"]);

  assert_eq!(output.status.code(), Some(1));
  assert_eq!(stdout(&output), "");
  assert_eq!(stderr(&output).lines().count(), 1, "{}", stderr(&output));
}

#[test]
fn list_reports_the_reason_when_the_server_is_down() {
  let sandbox = Sandbox::new("server-down");
  sandbox.fake_herdr(SERVER_DOWN_JSON, "", 1);

  let output = sandbox.run(&["list"]);

  assert_eq!(output.status.code(), Some(1));
  assert_eq!(stdout(&output), "");
  assert!(stderr(&output).contains("no herdr server is running"));
}

#[test]
fn list_fails_on_broken_json() {
  let sandbox = Sandbox::new("broken-json");
  sandbox.fake_herdr("not json", "", 0);

  let output = sandbox.run(&["list"]);

  assert_eq!(output.status.code(), Some(1));
  assert_eq!(stdout(&output), "");
}

#[test]
fn self_is_silent_outside_herdr() {
  let sandbox = Sandbox::new("self-no-pane");

  let output = sandbox.run(&["self"]);

  assert_eq!(output.status.code(), Some(0));
  assert_eq!(stdout(&output), "");
  assert_eq!(stderr(&output), "");
}

#[test]
fn self_is_silent_without_a_sidecar() {
  let sandbox = Sandbox::new("self-no-sidecar");

  let output = sandbox.run_in_pane(&["self"], "w3C:p1W");

  assert_eq!(output.status.code(), Some(0));
  assert_eq!(stdout(&output), "");
}

#[test]
fn self_prints_the_line_for_its_own_pane() {
  let sandbox = Sandbox::new("self-line");
  sandbox.sidecar("w3C_p1W.json", 15);

  let output = sandbox.run_in_pane(&["self"], "w3C:p1W");

  assert_eq!(output.status.code(), Some(0));
  let text = stdout(&output);
  assert_eq!(text.lines().count(), 1);
  assert!(
    text.starts_with("context 15% (pane w3C:p1W, model Fable 5.1, as of "),
    "{text}"
  );
}

#[test]
fn self_adds_the_handover_line_for_a_commander() {
  let sandbox = Sandbox::new("self-commander");
  sandbox.fake_herdr("", GET_COMMANDER_JSON, 0);
  sandbox.sidecar("w3C_p1W.json", 62);

  let output = sandbox.run_in_pane(&["self"], "w3C:p1W");

  assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
  let text = stdout(&output);
  assert_eq!(text.lines().count(), 2);
  assert!(text.contains("/wtclose"), "{text}");
}

#[test]
fn self_keeps_the_usage_line_when_herdr_is_missing_above_the_limit() {
  let sandbox = Sandbox::new("self-no-herdr");
  sandbox.sidecar("w3C_p1W.json", 62);

  let output = sandbox.run_in_pane(&["self"], "w3C:p1W");

  assert_eq!(output.status.code(), Some(0));
  let text = stdout(&output);
  assert_eq!(text.lines().count(), 1);
  assert!(text.starts_with("context 62% (pane w3C:p1W"), "{text}");
  assert_eq!(stderr(&output).lines().count(), 1);
}

#[test]
fn bad_arguments_exit_with_two() {
  let sandbox = Sandbox::new("bad-args");

  let output = sandbox.run(&["nope"]);

  assert_eq!(output.status.code(), Some(2));
  assert!(stderr(&output).contains("Usage"));
}

#[test]
fn watch_writes_agents_json_and_notifies_once_across_cycles() {
  let sandbox = Sandbox::new("watch");
  sandbox.fake_herdr(LIST_JSON, "", 0);
  sandbox.sidecar("w3C_p1W.json", 62);
  let ctx = sandbox.home().join(".herdr/ctx");

  let mut child = sandbox
    .command(&["watch", "--interval", "1"])
    .stdout(Stdio::null())
    .stderr(Stdio::null())
    .spawn()
    .expect("binary runs");

  let state_written = wait_for(&ctx.join("notify_state.json"));
  // 2 周期目以降も通知が増えないことを見るため、周期を跨いで待つ
  // Wait past another cycle to see that no second notification follows
  thread::sleep(Duration::from_millis(1500));
  child.kill().unwrap();
  child.wait().unwrap();

  assert!(state_written);
  let agents: serde_json::Value =
    serde_json::from_str(&fs::read_to_string(ctx.join("agents.json")).unwrap()).unwrap();
  assert_eq!(agents["agents"].as_array().unwrap().len(), 3);
  assert!(agents["generated_at"].is_string());

  let log = fs::read_to_string(sandbox.log()).unwrap();
  let notifications: Vec<&str> = log
    .lines()
    .filter(|line| line.starts_with("notification show"))
    .collect();
  assert_eq!(
    notifications,
    ["notification show commander-dotfiles context 62% --body dotfiles / working --sound request"]
  );
  assert!(
    log.lines().filter(|l| *l == "agent list").count() >= 2,
    "{log}"
  );
}

#[test]
fn watch_keeps_running_while_the_server_is_down() {
  let sandbox = Sandbox::new("watch-down");
  sandbox.fake_herdr(SERVER_DOWN_JSON, "", 1);

  let mut child = sandbox
    .command(&["watch", "--interval", "1"])
    .stdout(Stdio::null())
    .stderr(Stdio::null())
    .spawn()
    .expect("binary runs");

  thread::sleep(Duration::from_millis(1500));
  let still_running = child.try_wait().unwrap().is_none();
  child.kill().unwrap();
  child.wait().unwrap();

  assert!(still_running);
  assert!(!sandbox.home().join(".herdr/ctx/agents.json").exists());
}
