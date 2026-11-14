//! CLI の統合テスト。PATH の先に偽の herdr と偽の gh を置き、終了コードと stdout / stderr の約束を確かめる。
//! CLI integration tests. A fake herdr and a fake gh on PATH pin the contract on exit codes and
//! output streams.
//!
//! 偽の herdr と gh はシェルの組み込みコマンドだけを使う。ビルドサンドボックスの PATH に頼らないため。
//! リポジトリ・題・作者は架空の値で、本物の GitHub は呼ばない。
//! The fakes use shell builtins only, so they do not depend on the build sandbox's PATH. Every
//! repository, title and author is made up, and the real GitHub is never called.

use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::thread;
use std::time::{Duration, Instant};

const LIST_JSON: &str = r#"{"id":"cli:agent:list","result":{"agents":[{"agent":"claude","agent_session":{"value":"session-a"},"agent_status":"working","cwd":"/home/archie/dotfiles","name":"commander-dotfiles","pane_id":"w3C:p1W"},{"agent":"claude","agent_status":"idle","cwd":"/home/archie/notes","pane_id":"w3T:p2"},{"agent":"copilot","agent_status":"idle","cwd":"/home/archie/tools","pane_id":"w3U:p1"}]}}"#;
const GET_COMMANDER_JSON: &str = r#"{"id":"cli:agent:get","result":{"agent":{"name":"commander-dotfiles","pane_id":"w3C:p1W"},"type":"agent_info"}}"#;
const SHOWN_JSON: &str = r#"{"id":"cli:notification:show","result":{"reason":"shown","shown":true,"type":"notification_show"}}"#;
const NOT_SHOWN_JSON: &str = r#"{"id":"cli:notification:show","result":{"reason":"rate_limited","shown":false,"type":"notification_show"}}"#;
const SERVER_DOWN_JSON: &str = r#"{"id":"cli:agent:list","error":{"code":"server_not_running","message":"no herdr server is running"}}"#;
const SEARCH_JSON: &str = r#"{"total_count":2,"incomplete_results":false,"items":[{"repository_url":"https://api.github.com/repos/owner/zeta","html_url":"https://github.com/owner/zeta/pull/12","number":12,"title":"Add the widget","user":{"login":"author-a"},"draft":false,"updated_at":"2026-11-13T09:00:00Z","created_at":"2026-11-10T01:00:00Z"},{"repository_url":"https://api.github.com/repos/example-org/alpha","html_url":"https://github.com/example-org/alpha/pull/7","number":7,"title":"Fix the gadget","user":{"login":"author-b"},"draft":true,"updated_at":"2026-11-12T08:00:00Z","created_at":"2026-11-01T00:00:00Z"}]}"#;
const SEARCH_EMPTY_JSON: &str = r#"{"total_count":0,"incomplete_results":false,"items":[]}"#;
const BAD_CREDENTIALS_JSON: &str = r#"{"message":"Bad credentials","documentation_url":"https://docs.github.com/rest","status":"401"}"#;
const PREVIOUS_REVIEWS: &str = "{\"previous\":true}\n";

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

  fn gh_log(&self) -> PathBuf {
    self.root.join("gh.log")
  }

  fn reviews_file(&self) -> PathBuf {
    self.home().join(".herdr/ctx/reviews.json")
  }

  /// 呼ばれた引数を記録し、固定の stdout と stderr を返して exit_code で終わる偽の gh を置く。
  /// Installs a fake gh that logs its arguments, prints fixed stdout and stderr, and exits with
  /// exit_code.
  fn fake_gh(&self, stdout: &str, stderr: &str, exit_code: i32) {
    let script = format!(
      "#!/bin/sh\necho \"$*\" >> '{log}'\nprintf '%s' '{stdout}'\nprintf '%s' '{stderr}' >&2\nexit {exit_code}\n",
      log = self.gh_log().display(),
    );
    let path = self.bin().join("gh");
    fs::write(&path, script).unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
  }

  /// 応答せずに眠るだけの偽の gh を置く。
  /// Installs a fake gh that only sleeps and never answers.
  fn hanging_gh(&self) {
    let path = self.bin().join("gh");
    fs::write(&path, "#!/bin/sh\nsleep 5\n").unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
  }

  fn gh_calls(&self) -> usize {
    fs::read_to_string(self.gh_log()).map_or(0, |log| log.lines().count())
  }

  /// 呼ばれた引数を記録し、サブコマンドごとに固定の JSON を返す偽の herdr を置く。
  /// Installs a fake herdr that logs its arguments and answers each subcommand with fixed JSON.
  fn fake_herdr(&self, list: &str, get: &str, exit_code: i32) {
    self.fake_herdr_notifying(list, get, SHOWN_JSON, exit_code);
  }

  /// 応答せずに眠るだけの偽の herdr を置く。
  /// Installs a fake herdr that only sleeps and never answers.
  fn hanging_herdr(&self) {
    let path = self.bin().join("herdr");
    fs::write(&path, "#!/bin/sh\nsleep 5\n").unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
  }

  /// 偽の herdr が sleep を見つけられるように PATH の先頭に足し、期限を 1 秒にして実行する。
  /// Prepends to PATH so the fake herdr can find sleep, and shortens the deadline to one second.
  fn command_with_short_deadline(&self, args: &[&str]) -> Command {
    let mut command = self.command(args);
    command
      .env(
        "PATH",
        format!(
          "{}:{}",
          self.bin().display(),
          std::env::var("PATH").unwrap_or_default()
        ),
      )
      .env("HERDR_CTX_TIMEOUT_SECS", "1");
    command
  }

  fn fake_herdr_notifying(&self, list: &str, get: &str, notify: &str, exit_code: i32) {
    let script = format!(
      "#!/bin/sh\necho \"$*\" >> '{log}'\ncase \"$1 $2\" in\n  'agent list') printf '%s\\n' '{list}' ;;\n  'agent get') printf '%s\\n' '{get}' ;;\n  'notification show') printf '%s\\n' '{notify}' ;;\nesac\nexit {exit_code}\n",
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
      r#"{{"pane_id":"w3C:p1W","session_id":"session-a","transcript_path":"/t/a.jsonl","used_percentage":{pct},"context_window_size":1000000,"total_input_tokens":620000,"model_id":"claude-fable-5-1","model_name":"Fable 5.1","updated_at":"2020-01-01T00:00:00Z"}}"#
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

  fn run_with_stdin(&self, args: &[&str], pane_id: &str, input: &str) -> Output {
    let mut child = self
      .command(args)
      .env("HERDR_PANE_ID", pane_id)
      .stdin(Stdio::piped())
      .stdout(Stdio::piped())
      .stderr(Stdio::piped())
      .spawn()
      .expect("binary runs");
    child
      .stdin
      .take()
      .unwrap()
      .write_all(input.as_bytes())
      .unwrap();
    child.wait_with_output().expect("binary runs")
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

fn wait_until(condition: impl Fn() -> bool) -> bool {
  let deadline = Instant::now() + Duration::from_secs(10);
  while Instant::now() < deadline {
    if condition() {
      return true;
    }
    thread::sleep(Duration::from_millis(50));
  }
  false
}

fn wait_for(path: &Path) -> bool {
  wait_until(|| path.exists())
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
  assert_eq!(first["session_match"], true);
  let second: serde_json::Value = serde_json::from_str(lines[1]).unwrap();
  assert_eq!(second["note"], "no sidecar");
  let third: serde_json::Value = serde_json::from_str(lines[2]).unwrap();
  assert!(third["pct"].is_null());
  assert_eq!(third["note"], "not a claude agent");
}

#[test]
fn list_keeps_the_value_and_marks_a_sidecar_of_another_session() {
  let sandbox = Sandbox::new("list-mismatch");
  sandbox.fake_herdr(&LIST_JSON.replace("session-a", "session-z"), "", 0);
  sandbox.sidecar("w3C_p1W.json", 62);

  let json = stdout(&sandbox.run(&["list"]));
  let first: serde_json::Value = serde_json::from_str(json.lines().next().unwrap()).unwrap();
  assert_eq!(first["session_match"], false);
  assert_eq!(first["pct"], 62);

  let table = stdout(&sandbox.run(&["list", "--table"]));
  assert!(table.contains("62% (session?)"), "{table}");
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
fn list_gives_up_on_a_hanging_herdr_at_the_deadline() {
  let sandbox = Sandbox::new("list-hang");
  sandbox.hanging_herdr();

  let started = Instant::now();
  let output = sandbox
    .command_with_short_deadline(&["list"])
    .output()
    .expect("binary runs");

  assert!(started.elapsed() < Duration::from_secs(2));
  assert_eq!(output.status.code(), Some(1));
  assert_eq!(stdout(&output), "");
  assert_eq!(
    stderr(&output).trim_end(),
    "herdr-ctx: herdr が 1 秒以内に応答しない"
  );
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
fn self_stays_silent_when_neither_key_matches_the_hook() {
  let sandbox = Sandbox::new("self-other-session");
  sandbox.sidecar("w3C_p1W.json", 62);

  let input = r#"{"session_id":"session-b","transcript_path":"/t/b.jsonl","prompt":"hi"}"#;
  let output = sandbox.run_with_stdin(&["self"], "w3C:p1W", input);

  assert_eq!(output.status.code(), Some(0));
  assert_eq!(stdout(&output), "");
  assert_eq!(
    stderr(&output).trim_end(),
    "herdr-ctx: sidecar は別の session のもの"
  );
}

#[test]
fn self_prints_when_the_session_id_differs_but_the_transcript_path_matches() {
  let sandbox = Sandbox::new("self-same-transcript");
  sandbox.sidecar("w3C_p1W.json", 15);

  let input = r#"{"session_id":"session-b","transcript_path":"/t/a.jsonl"}"#;
  let output = sandbox.run_with_stdin(&["self"], "w3C:p1W", input);

  assert_eq!(output.status.code(), Some(0));
  assert!(
    stdout(&output).starts_with("context 15% "),
    "{}",
    stdout(&output)
  );
}

#[test]
fn self_prints_when_the_session_id_matches() {
  let sandbox = Sandbox::new("self-same-session");
  sandbox.sidecar("w3C_p1W.json", 15);

  let input = r#"{"session_id":"session-a","transcript_path":"/t/b.jsonl"}"#;
  let output = sandbox.run_with_stdin(&["self"], "w3C:p1W", input);

  assert!(
    stdout(&output).starts_with("context 15% "),
    "{}",
    stdout(&output)
  );
}

#[test]
fn self_skips_the_check_without_json_on_stdin() {
  let sandbox = Sandbox::new("self-no-json");
  sandbox.sidecar("w3C_p1W.json", 15);

  for input in ["", "not json"] {
    let output = sandbox.run_with_stdin(&["self"], "w3C:p1W", input);
    assert!(stdout(&output).starts_with("context 15% "), "{input:?}");
  }
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
fn self_keeps_the_usage_line_when_herdr_hangs_above_the_limit() {
  let sandbox = Sandbox::new("self-hang");
  sandbox.hanging_herdr();
  sandbox.sidecar("w3C_p1W.json", 62);

  let started = Instant::now();
  let output = sandbox
    .command_with_short_deadline(&["self"])
    .env("HERDR_PANE_ID", "w3C:p1W")
    .output()
    .expect("binary runs");

  assert!(started.elapsed() < Duration::from_secs(2));
  assert_eq!(output.status.code(), Some(0));
  let text = stdout(&output);
  assert_eq!(text.lines().count(), 1);
  assert!(text.starts_with("context 62% (pane w3C:p1W"), "{text}");
  assert!(stderr(&output).contains("herdr が 1 秒以内に応答しない"));
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
  // PATH に gh が無いので、reviews.json は作られない / No gh on PATH, so no reviews.json
  assert!(!ctx.join("reviews.json").exists());

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
fn watch_retries_a_notice_that_herdr_did_not_show() {
  let sandbox = Sandbox::new("watch-not-shown");
  sandbox.fake_herdr_notifying(LIST_JSON, "", NOT_SHOWN_JSON, 0);
  sandbox.sidecar("w3C_p1W.json", 62);
  let ctx = sandbox.home().join(".herdr/ctx");

  let mut child = sandbox
    .command(&["watch", "--interval", "1"])
    .stdout(Stdio::null())
    .stderr(Stdio::null())
    .spawn()
    .expect("binary runs");

  let agents_written = wait_for(&ctx.join("agents.json"));
  thread::sleep(Duration::from_millis(1500));
  child.kill().unwrap();
  child.wait().unwrap();

  assert!(agents_written);
  let log = fs::read_to_string(sandbox.log()).unwrap();
  let attempts = log
    .lines()
    .filter(|line| line.starts_with("notification show"))
    .count();
  assert!(attempts >= 2, "{log}");
  assert!(!ctx.join("notify_state.json").exists());
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

#[test]
fn reviews_prints_the_requests_as_json() {
  let sandbox = Sandbox::new("reviews");
  sandbox.fake_gh(SEARCH_JSON, "", 0);

  let output = sandbox.run(&["reviews"]);

  assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
  assert_eq!(stderr(&output), "");
  let reviews: serde_json::Value = serde_json::from_str(&stdout(&output)).unwrap();
  assert!(reviews["generated_at"].is_string());
  assert_eq!(reviews["total_count"], 2);
  let requests = reviews["review_requests"].as_array().unwrap();
  assert_eq!(requests.len(), 2);
  assert_eq!(requests[0]["repo"], "owner/zeta");
  assert_eq!(requests[0]["number"], 12);
  assert_eq!(requests[0]["url"], "https://github.com/owner/zeta/pull/12");
  assert_eq!(requests[0]["author"], "author-a");
  assert_eq!(requests[1]["repo"], "example-org/alpha");
  assert_eq!(requests[1]["draft"], true);

  let log = fs::read_to_string(sandbox.gh_log()).unwrap();
  assert_eq!(
    log.trim_end(),
    "api -X GET search/issues -f q=is:pr is:open user-review-requested:@me -f per_page=100 -f sort=updated -f order=desc"
  );
  // reviews は stdout に出すだけで、ファイルは書かない / reviews only prints; it writes no file
  assert!(!sandbox.reviews_file().exists());
}

#[test]
fn reviews_prints_an_empty_list_when_nothing_is_requested() {
  let sandbox = Sandbox::new("reviews-empty");
  sandbox.fake_gh(SEARCH_EMPTY_JSON, "", 0);

  let output = sandbox.run(&["reviews"]);

  assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
  let reviews: serde_json::Value = serde_json::from_str(&stdout(&output)).unwrap();
  assert_eq!(reviews["total_count"], 0);
  assert!(reviews["review_requests"].as_array().unwrap().is_empty());
}

#[test]
fn reviews_reports_the_reason_when_gh_fails() {
  let sandbox = Sandbox::new("reviews-fail");
  sandbox.fake_gh(BAD_CREDENTIALS_JSON, "gh: Bad credentials (HTTP 401)\n", 1);

  let output = sandbox.run(&["reviews"]);

  assert_eq!(output.status.code(), Some(1));
  assert_eq!(stdout(&output), "");
  assert_eq!(
    stderr(&output),
    "herdr-ctx: gh: Bad credentials (HTTP 401)\n"
  );
}

#[test]
fn reviews_fails_on_broken_json() {
  let sandbox = Sandbox::new("reviews-broken");
  sandbox.fake_gh("not json", "", 0);

  let output = sandbox.run(&["reviews"]);

  assert_eq!(output.status.code(), Some(1));
  assert_eq!(stdout(&output), "");
  assert_eq!(stderr(&output).lines().count(), 1, "{}", stderr(&output));
  assert!(stderr(&output).contains("GitHub の JSON を読めない"));
}

#[test]
fn reviews_without_gh_fails_with_one_stderr_line() {
  let sandbox = Sandbox::new("reviews-no-gh");

  let output = sandbox.run(&["reviews"]);

  assert_eq!(output.status.code(), Some(1));
  assert_eq!(stdout(&output), "");
  assert_eq!(stderr(&output).lines().count(), 1, "{}", stderr(&output));
  assert!(stderr(&output).starts_with("herdr-ctx: gh を実行できない"));
}

#[test]
fn reviews_gives_up_on_a_hanging_gh_at_the_deadline() {
  let sandbox = Sandbox::new("reviews-hang");
  sandbox.hanging_gh();

  let started = Instant::now();
  let output = sandbox
    .command_with_short_deadline(&["reviews"])
    .output()
    .expect("binary runs");

  assert!(started.elapsed() < Duration::from_secs(2));
  assert_eq!(output.status.code(), Some(1));
  assert_eq!(stdout(&output), "");
  assert_eq!(
    stderr(&output).trim_end(),
    "herdr-ctx: gh が 1 秒以内に応答しない"
  );
}

fn spawn_watch(sandbox: &Sandbox) -> std::process::Child {
  sandbox
    .command(&["watch", "--interval", "1", "--reviews-interval", "1"])
    .stdout(Stdio::null())
    .stderr(Stdio::piped())
    .spawn()
    .expect("binary runs")
}

fn stop(mut child: std::process::Child) -> String {
  child.kill().unwrap();
  let output = child.wait_with_output().unwrap();
  stderr(&output)
}

#[test]
fn watch_writes_reviews_json() {
  let sandbox = Sandbox::new("watch-reviews");
  sandbox.fake_herdr(LIST_JSON, "", 0);
  sandbox.fake_gh(SEARCH_JSON, "", 0);
  let ctx = sandbox.home().join(".herdr/ctx");

  let child = spawn_watch(&sandbox);
  let written = wait_for(&sandbox.reviews_file()) && wait_for(&ctx.join("agents.json"));
  let log = stop(child);

  assert!(written, "{log}");
  let reviews: serde_json::Value =
    serde_json::from_str(&fs::read_to_string(sandbox.reviews_file()).unwrap()).unwrap();
  assert!(reviews["generated_at"].is_string());
  assert_eq!(reviews["total_count"], 2);
  assert_eq!(reviews["review_requests"][0]["repo"], "owner/zeta");
}

#[test]
fn watch_overwrites_reviews_json_with_an_empty_list_when_nothing_is_requested() {
  let sandbox = Sandbox::new("watch-reviews-empty");
  sandbox.fake_herdr(LIST_JSON, "", 0);
  sandbox.fake_gh(SEARCH_EMPTY_JSON, "", 0);
  fs::write(sandbox.reviews_file(), PREVIOUS_REVIEWS).unwrap();

  let child = spawn_watch(&sandbox);
  let replaced = wait_until(|| {
    fs::read_to_string(sandbox.reviews_file()).is_ok_and(|text| text != PREVIOUS_REVIEWS)
  });
  let log = stop(child);

  assert!(replaced, "{log}");
  let reviews: serde_json::Value =
    serde_json::from_str(&fs::read_to_string(sandbox.reviews_file()).unwrap()).unwrap();
  assert_eq!(reviews["total_count"], 0);
  assert!(reviews["review_requests"].as_array().unwrap().is_empty());
}

#[test]
fn watch_keeps_reviews_json_and_the_agent_cycle_when_gh_fails() {
  let sandbox = Sandbox::new("watch-reviews-fail");
  sandbox.fake_herdr(LIST_JSON, "", 0);
  sandbox.fake_gh(BAD_CREDENTIALS_JSON, "gh: Bad credentials (HTTP 401)\n", 1);
  sandbox.sidecar("w3C_p1W.json", 62);
  fs::write(sandbox.reviews_file(), PREVIOUS_REVIEWS).unwrap();
  let ctx = sandbox.home().join(".herdr/ctx");

  let child = spawn_watch(&sandbox);
  // 失敗した周期を 2 回見てから止める / Stop after two failed cycles
  let retried = wait_until(|| sandbox.gh_calls() >= 2);
  let agents_written = wait_for(&ctx.join("notify_state.json"));
  let log = stop(child);

  assert!(retried && agents_written, "{log}");
  assert_eq!(
    fs::read_to_string(sandbox.reviews_file()).unwrap(),
    PREVIOUS_REVIEWS
  );
  assert!(ctx.join("agents.json").exists());
  let herdr_log = fs::read_to_string(sandbox.log()).unwrap();
  assert!(
    herdr_log
      .lines()
      .any(|line| line.starts_with("notification show")),
    "{herdr_log}"
  );
  assert!(
    log
      .lines()
      .any(|line| line == "herdr-ctx: レビュー依頼を更新できない: gh: Bad credentials (HTTP 401)"),
    "{log}"
  );
}

#[test]
fn watch_keeps_the_agent_cycle_while_gh_hangs() {
  let sandbox = Sandbox::new("watch-gh-hang");
  sandbox.fake_herdr(LIST_JSON, "", 0);
  sandbox.hanging_gh();

  // gh の期限は既定の 15 秒のまま。agent の周期がそれを待たないことを見る
  // gh keeps its default 15 second deadline; the agent cycle must not wait for it
  let mut child = sandbox
    .command(&["watch", "--interval", "1"])
    .env(
      "PATH",
      format!(
        "{}:{}",
        sandbox.bin().display(),
        std::env::var("PATH").unwrap_or_default()
      ),
    )
    .stdout(Stdio::null())
    .stderr(Stdio::null())
    .spawn()
    .expect("binary runs");

  let cycled = wait_until(|| {
    fs::read_to_string(sandbox.log())
      .is_ok_and(|log| log.lines().filter(|line| *line == "agent list").count() >= 3)
  });
  child.kill().unwrap();
  child.wait().unwrap();

  assert!(cycled);
  assert!(!sandbox.reviews_file().exists());
}
