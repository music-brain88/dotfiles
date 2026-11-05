//! herdr-ctx — herdr の各 agent の context 使用率を、pane の幅に依存せず読む (Issue #784)。
//! Reads each herdr agent's context usage regardless of pane width (Issue #784).
//!
//! 数値の出所は Claude Code の statusline が書く sidecar で、transcript の JSONL は読まない。
//! The numbers come from the sidecar the Claude Code statusline writes, never from the
//! transcript JSONL.
//!
//! 終了コード / Exit code:
//!   0  成功。self は hook から呼ぶので常に 0 で、値が無いときは何も出さない
//!   1  herdr が無い、JSON を読めない、herdr に繋がらない(list)
//!   2  引数が正しくない

mod herdr;
mod report;
mod sidecar;
mod watch;

use chrono::{Local, Utc};
use herdr::HerdrCli;
use std::env;
use std::io::{IsTerminal, Read, Write};
use std::path::PathBuf;
use std::process::ExitCode;
use std::time::Duration;
use watch::WatchOptions;

/// herdr の応答を待つ上限。self は hook の timeout(5 秒)より短くして、1 行目を出す時間を残す。
/// How long to wait for herdr. self stays under the 5 second hook timeout to still print its line.
const QUERY_TIMEOUT_SECS: u64 = 3;
const WATCH_TIMEOUT_SECS: u64 = 10;

/// 上の期限を上書きする環境変数。統合テストが期限を短くするために使う。
/// Overrides the deadlines above; integration tests use it to shorten them.
const TIMEOUT_ENV: &str = "HERDR_CTX_TIMEOUT_SECS";

const USAGE: &str = "\
使い方 / Usage:
  herdr-ctx list [--table]
  herdr-ctx self
  herdr-ctx watch [--interval <秒>] [--thresholds <カンマ区切り>]
";

#[derive(Debug, PartialEq)]
enum Cmd {
  List { table: bool },
  SelfReport,
  Watch(WatchOptions),
  Help,
}

fn parse_watch<'a>(mut args: impl Iterator<Item = &'a str>) -> Result<WatchOptions, String> {
  let mut interval = watch::DEFAULT_INTERVAL_SECS;
  let mut thresholds = watch::DEFAULT_THRESHOLDS.to_vec();
  while let Some(arg) = args.next() {
    match arg {
      "--interval" => {
        let value = args.next().ok_or("--interval に値が無い")?;
        interval = value
          .parse()
          .ok()
          .filter(|secs| *secs > 0)
          .ok_or_else(|| format!("--interval は 1 以上の整数で指定する: {value}"))?;
      }
      "--thresholds" => {
        thresholds = watch::parse_thresholds(args.next().ok_or("--thresholds に値が無い")?)?;
      }
      other => return Err(format!("不明な引数: {other}")),
    }
  }
  Ok(WatchOptions {
    interval: Duration::from_secs(interval),
    thresholds,
  })
}

fn parse_args(args: &[String]) -> Result<Cmd, String> {
  let mut args = args.iter().map(String::as_str);
  let subcommand = args.next().ok_or("サブコマンドが無い")?;
  match subcommand {
    "list" => {
      let mut table = false;
      for arg in args {
        match arg {
          "--table" => table = true,
          other => return Err(format!("不明な引数: {other}")),
        }
      }
      Ok(Cmd::List { table })
    }
    "self" => match args.next() {
      Some(other) => Err(format!("不明な引数: {other}")),
      None => Ok(Cmd::SelfReport),
    },
    "watch" => parse_watch(args).map(Cmd::Watch),
    "-h" | "--help" | "help" => Ok(Cmd::Help),
    other => Err(format!("不明なサブコマンド: {other}")),
  }
}

fn herdr_cli(default_secs: u64) -> HerdrCli {
  let secs = env::var(TIMEOUT_ENV)
    .ok()
    .and_then(|value| value.parse().ok())
    .filter(|secs| *secs > 0)
    .unwrap_or(default_secs);
  HerdrCli::new(Duration::from_secs(secs))
}

fn ctx_dir() -> Option<PathBuf> {
  let home = env::var_os("HOME").filter(|home| !home.is_empty())?;
  Some(PathBuf::from(home).join(".herdr/ctx"))
}

/// `herdr-ctx list | head -1` のように読み手が先に閉じても、panic せずに終わる。
/// Ends quietly even if the reader closes first, as in `herdr-ctx list | head -1`.
fn emit(text: &str) {
  let _ = std::io::stdout().write_all(text.as_bytes());
}

fn fail(reason: &str) -> ExitCode {
  eprintln!("herdr-ctx: {reason}");
  ExitCode::from(1)
}

fn run_list(table: bool) -> ExitCode {
  let Some(dir) = ctx_dir() else {
    return fail("HOME が無い");
  };
  let herdr = herdr_cli(QUERY_TIMEOUT_SECS);
  let rows = match report::collect_rows(&herdr, &dir.join("panes"), Utc::now()) {
    Ok(rows) => rows,
    Err(reason) => return fail(&reason),
  };
  if table {
    emit(&report::table(&rows, &Local));
    return ExitCode::SUCCESS;
  }
  match report::json_lines(&rows) {
    Ok(text) => {
      emit(&text);
      ExitCode::SUCCESS
    }
    Err(reason) => fail(&reason),
  }
}

/// hook が stdin に渡す JSON を読む。stdin が端末のときは読まない。手で打った `herdr-ctx self` が
/// 入力待ちで止まらないようにするため。
/// Reads the JSON the hook passes on stdin, skipping a terminal so a manual `herdr-ctx self` does
/// not block waiting for input.
fn read_hook_input() -> Option<report::HookInput> {
  let mut stdin = std::io::stdin();
  if stdin.is_terminal() {
    return None;
  }
  let mut text = String::new();
  stdin.read_to_string(&mut text).ok()?;
  report::HookInput::parse(&text)
}

fn run_self() -> ExitCode {
  let Some(dir) = ctx_dir() else {
    return ExitCode::SUCCESS;
  };
  let pane_id = env::var("HERDR_PANE_ID").ok().filter(|id| !id.is_empty());
  let hook = read_hook_input();
  let text = report::self_report(
    &herdr_cli(QUERY_TIMEOUT_SECS),
    &dir.join("panes"),
    pane_id.as_deref(),
    hook.as_ref(),
    &Local,
  );
  if let Some(text) = text {
    emit(&text);
  }
  ExitCode::SUCCESS
}

fn main() -> ExitCode {
  let args: Vec<String> = env::args().skip(1).collect();
  let cmd = match parse_args(&args) {
    Ok(cmd) => cmd,
    Err(reason) => {
      eprintln!("herdr-ctx: {reason}");
      eprint!("{USAGE}");
      return ExitCode::from(2);
    }
  };
  match cmd {
    Cmd::List { table } => run_list(table),
    Cmd::SelfReport => run_self(),
    Cmd::Watch(options) => match ctx_dir() {
      Some(dir) => watch::run(&herdr_cli(WATCH_TIMEOUT_SECS), &dir, &options),
      None => fail("HOME が無い"),
    },
    Cmd::Help => {
      emit(USAGE);
      ExitCode::SUCCESS
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn parse(args: &[&str]) -> Result<Cmd, String> {
    let args: Vec<String> = args.iter().map(|arg| arg.to_string()).collect();
    parse_args(&args)
  }

  #[test]
  fn list_takes_an_optional_table_flag() {
    assert_eq!(parse(&["list"]), Ok(Cmd::List { table: false }));
    assert_eq!(parse(&["list", "--table"]), Ok(Cmd::List { table: true }));
    assert!(parse(&["list", "--wide"]).is_err());
  }

  #[test]
  fn watch_defaults_to_thirty_seconds_and_fifty_sixty_eighty() {
    assert_eq!(
      parse(&["watch"]),
      Ok(Cmd::Watch(WatchOptions {
        interval: Duration::from_secs(30),
        thresholds: vec![50, 60, 80],
      }))
    );
  }

  #[test]
  fn watch_accepts_both_options() {
    assert_eq!(
      parse(&["watch", "--interval", "5", "--thresholds", "1,2,3"]),
      Ok(Cmd::Watch(WatchOptions {
        interval: Duration::from_secs(5),
        thresholds: vec![1, 2, 3],
      }))
    );
  }

  #[test]
  fn watch_rejects_a_bad_interval() {
    assert!(parse(&["watch", "--interval", "0"]).is_err());
    assert!(parse(&["watch", "--interval", "x"]).is_err());
    assert!(parse(&["watch", "--interval"]).is_err());
  }

  #[test]
  fn unknown_input_is_an_error() {
    assert!(parse(&[]).is_err());
    assert!(parse(&["nope"]).is_err());
    assert!(parse(&["self", "extra"]).is_err());
  }
}

/// テスト共通の偽 herdr と固定の JSON。形は herdr 0.9.5 の実際の応答に合わせてある。
/// A shared fake herdr and fixed JSON, shaped like real herdr 0.9.5 responses.
#[cfg(test)]
pub mod testutil {
  use crate::herdr::Herdr;
  use std::cell::RefCell;
  use std::fs;
  use std::path::PathBuf;

  pub const AGENT_LIST_JSON: &str = r#"{"id":"cli:agent:list","result":{"agents":[
    {"agent":"claude","agent_session":{"agent":"claude","kind":"id","source":"herdr:claude","value":"session-a"},"agent_status":"working","cwd":"/home/archie/dotfiles","name":"commander-dotfiles","pane_id":"w3C:p1W","workspace_id":"w3C"},
    {"agent":"claude","agent_status":"idle","cwd":"/home/archie/notes","pane_id":"w3T:p2","workspace_id":"w3T"},
    {"agent":"copilot","agent_status":"idle","cwd":"/home/archie/tools","pane_id":"w3U:p1","workspace_id":"w3U"}
  ]}}"#;

  pub const AGENT_GET_JSON: &str = r#"{"id":"cli:agent:get","result":{"agent":{"agent":"claude","agent_status":"working","cwd":"/home/archie/dotfiles","name":"commander-dotfiles","pane_id":"w3C:p1W"},"type":"agent_info"}}"#;

  pub const NOTIFY_SHOWN_JSON: &str = r#"{"id":"cli:notification:show","result":{"reason":"shown","shown":true,"type":"notification_show"}}"#;

  pub const NOTIFY_NOT_SHOWN_JSON: &str = r#"{"id":"cli:notification:show","result":{"reason":"rate_limited","shown":false,"type":"notification_show"}}"#;

  pub struct FakeHerdr {
    pub list: Result<String, String>,
    pub get: Result<String, String>,
    pub notify_result: Result<String, String>,
    pub notified: RefCell<Vec<(String, String)>>,
  }

  impl FakeHerdr {
    pub fn with_list(list: &str) -> Self {
      Self {
        list: Ok(list.to_string()),
        get: Err("agent get is not set up".to_string()),
        notify_result: Ok(NOTIFY_SHOWN_JSON.to_string()),
        notified: RefCell::new(Vec::new()),
      }
    }
  }

  impl Herdr for FakeHerdr {
    fn agent_list(&self) -> Result<String, String> {
      self.list.clone()
    }

    fn agent_get(&self, _target: &str) -> Result<String, String> {
      self.get.clone()
    }

    fn notify(&self, title: &str, body: &str) -> Result<String, String> {
      let response = self.notify_result.clone()?;
      self
        .notified
        .borrow_mut()
        .push((title.to_string(), body.to_string()));
      Ok(response)
    }
  }

  /// テストごとに空のディレクトリを作る。名前は呼び出し側で一意にする。
  /// Creates an empty directory per test. Callers keep the names unique.
  pub fn temp_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("herdr-ctx-{}-{name}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
  }
}
