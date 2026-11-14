//! herdr-ctx — 司令塔と決定者が見る盤面のために、機械が取れる値を集める計器。
//! The instrument that gathers machine-readable values for the board the commander and the
//! decision maker share.
//!
//! 集める値は 2 つある。herdr の各 agent の context 使用率を pane の幅に依存せず読み (Issue #784)、
//! 決定者に割り当てられた open のレビュー依頼を GitHub から集める (Issue #805)。
//! It gathers two values: each herdr agent's context usage regardless of pane width (Issue #784),
//! and the open review requests assigned to the decision maker on GitHub (Issue #805).
//!
//! 使用率の出所は Claude Code の statusline が書く sidecar で、transcript の JSONL は読まない。
//! レビュー依頼は `gh api` で取り、認証は gh に任せる。
//! Usage comes from the sidecar the Claude Code statusline writes, never from the transcript
//! JSONL. Review requests come from `gh api`, which handles authentication.
//!
//! 終了コード / Exit code:
//!   0  成功。self は hook から呼ぶので常に 0 で、値が無いときは何も出さない
//!   1  herdr が無い、JSON を読めない、herdr に繋がらない(list)。gh が無い、gh が失敗した、
//!      応答を読めない(reviews)
//!   2  引数が正しくない

mod github;
mod herdr;
mod process;
mod report;
mod sidecar;
mod watch;

use chrono::{Local, Utc};
use github::GhCli;
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

/// gh の応答を待つ上限。検索 API はふだん数秒で返る。watch では専用のスレッドが待つので、
/// この期限が agent の一覧の周期を遅らせることはない。
/// How long to wait for gh. The search API usually answers within seconds. In watch a dedicated
/// thread does the waiting, so this deadline never delays the agent cycle.
const GH_TIMEOUT_SECS: u64 = 15;

/// 上の期限(herdr と gh の両方)を上書きする環境変数。統合テストが期限を短くするために使う。
/// Overrides the deadlines above, for both herdr and gh; integration tests use it to shorten them.
const TIMEOUT_ENV: &str = "HERDR_CTX_TIMEOUT_SECS";

const USAGE: &str = "\
使い方 / Usage:
  herdr-ctx list [--table]
  herdr-ctx self
  herdr-ctx reviews
  herdr-ctx watch [--interval <秒>] [--thresholds <カンマ区切り>] [--reviews-interval <秒>]
";

#[derive(Debug, PartialEq)]
enum Cmd {
  List { table: bool },
  SelfReport,
  Reviews,
  Watch(WatchOptions),
  Help,
}

fn parse_secs(flag: &str, value: Option<&str>) -> Result<Duration, String> {
  let value = value.ok_or_else(|| format!("{flag} に値が無い"))?;
  value
    .parse()
    .ok()
    .filter(|secs| *secs > 0)
    .map(Duration::from_secs)
    .ok_or_else(|| format!("{flag} は 1 以上の整数で指定する: {value}"))
}

fn parse_watch<'a>(mut args: impl Iterator<Item = &'a str>) -> Result<WatchOptions, String> {
  let mut options = WatchOptions {
    interval: Duration::from_secs(watch::DEFAULT_INTERVAL_SECS),
    thresholds: watch::DEFAULT_THRESHOLDS.to_vec(),
    reviews_interval: Duration::from_secs(watch::DEFAULT_REVIEWS_INTERVAL_SECS),
  };
  while let Some(arg) = args.next() {
    match arg {
      "--interval" => options.interval = parse_secs(arg, args.next())?,
      "--reviews-interval" => options.reviews_interval = parse_secs(arg, args.next())?,
      "--thresholds" => {
        options.thresholds =
          watch::parse_thresholds(args.next().ok_or("--thresholds に値が無い")?)?;
      }
      other => return Err(format!("不明な引数: {other}")),
    }
  }
  Ok(options)
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
    "reviews" => match args.next() {
      Some(other) => Err(format!("不明な引数: {other}")),
      None => Ok(Cmd::Reviews),
    },
    "watch" => parse_watch(args).map(Cmd::Watch),
    "-h" | "--help" | "help" => Ok(Cmd::Help),
    other => Err(format!("不明なサブコマンド: {other}")),
  }
}

fn deadline(default_secs: u64) -> Duration {
  let secs = env::var(TIMEOUT_ENV)
    .ok()
    .and_then(|value| value.parse().ok())
    .filter(|secs| *secs > 0)
    .unwrap_or(default_secs);
  Duration::from_secs(secs)
}

fn herdr_cli(default_secs: u64) -> HerdrCli {
  HerdrCli::new(deadline(default_secs))
}

fn gh_cli() -> GhCli {
  GhCli::new(deadline(GH_TIMEOUT_SECS))
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

fn run_reviews() -> ExitCode {
  match github::fetch_reviews(&gh_cli(), Utc::now()).and_then(|reviews| reviews.to_json()) {
    Ok(text) => {
      emit(&text);
      ExitCode::SUCCESS
    }
    Err(reason) => fail(&reason),
  }
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
    Cmd::Reviews => run_reviews(),
    Cmd::Watch(options) => match ctx_dir() {
      Some(dir) => watch::run(&herdr_cli(WATCH_TIMEOUT_SECS), gh_cli(), &dir, &options),
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
  fn watch_defaults_to_thirty_seconds_fifty_sixty_eighty_and_five_minutes() {
    assert_eq!(
      parse(&["watch"]),
      Ok(Cmd::Watch(WatchOptions {
        interval: Duration::from_secs(30),
        thresholds: vec![50, 60, 80],
        reviews_interval: Duration::from_secs(300),
      }))
    );
  }

  #[test]
  fn watch_accepts_every_option() {
    assert_eq!(
      parse(&[
        "watch",
        "--interval",
        "5",
        "--thresholds",
        "1,2,3",
        "--reviews-interval",
        "60",
      ]),
      Ok(Cmd::Watch(WatchOptions {
        interval: Duration::from_secs(5),
        thresholds: vec![1, 2, 3],
        reviews_interval: Duration::from_secs(60),
      }))
    );
  }

  #[test]
  fn watch_rejects_a_bad_interval() {
    for flag in ["--interval", "--reviews-interval"] {
      assert!(parse(&["watch", flag, "0"]).is_err(), "{flag}");
      assert!(parse(&["watch", flag, "x"]).is_err(), "{flag}");
      assert!(parse(&["watch", flag]).is_err(), "{flag}");
    }
  }

  #[test]
  fn reviews_takes_no_arguments() {
    assert_eq!(parse(&["reviews"]), Ok(Cmd::Reviews));
    assert!(parse(&["reviews", "--all"]).is_err());
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
  use crate::github::GitHub;
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

  /// 検索 API の応答の形。リポジトリ・題・作者はすべて架空の値である。total_count が items より多いのは、
  /// 先頭の 100 件だけを受け取る場合を表す。
  /// Shaped like a search API response, with made-up repositories, titles and authors. total_count
  /// above the item count stands for receiving only the first 100.
  pub const SEARCH_JSON: &str = r#"{"total_count":152,"incomplete_results":false,"items":[
    {"url":"https://api.github.com/repos/owner/zeta/issues/123","repository_url":"https://api.github.com/repos/owner/zeta","html_url":"https://github.com/owner/zeta/pull/123","number":123,"title":"Add the widget","user":{"login":"author-a","id":1},"state":"open","draft":false,"pull_request":{"url":"https://api.github.com/repos/owner/zeta/pulls/123"},"updated_at":"2026-11-13T09:00:00Z","created_at":"2026-11-10T01:00:00Z"},
    {"repository_url":"https://api.github.com/repos/example-org/alpha","html_url":"https://github.com/example-org/alpha/pull/7","number":7,"title":"Fix the gadget","user":{"login":"author-b"},"draft":true,"updated_at":"2026-11-12T08:00:00Z","created_at":"2026-11-01T00:00:00Z"},
    {"repository_url":"https://api.github.com/repos/owner/zeta","html_url":"https://github.com/owner/zeta/pull/98","number":98,"title":"Tidy the docs","user":null,"updated_at":"2026-11-02T00:00:00Z","created_at":"2026-10-30T00:00:00Z"}
  ]}"#;

  pub const SEARCH_EMPTY_JSON: &str = r#"{"total_count":0,"incomplete_results":false,"items":[]}"#;

  pub struct FakeGitHub {
    pub search: Result<String, String>,
  }

  impl FakeGitHub {
    pub fn answering(raw: &str) -> Self {
      Self {
        search: Ok(raw.to_string()),
      }
    }

    pub fn failing(reason: &str) -> Self {
      Self {
        search: Err(reason.to_string()),
      }
    }
  }

  impl GitHub for FakeGitHub {
    fn search_review_requests(&self) -> Result<String, String> {
      self.search.clone()
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
