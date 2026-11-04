//! 常駐のループ。agents.json を書き、閾値を下から上に跨いだ agent を 1 回だけ知らせる。
//! SIGTERM は既定の動作のままにする。書き込みは一時ファイル + rename なので、途中で落ちても
//! 読む側に書きかけのファイルは見えず、systemd は SIGTERM での終了を正常終了として扱う。
//! The resident loop: writes agents.json and notifies once per upward threshold crossing.
//! SIGTERM keeps its default action. Writes go through a temp file and rename, so dying mid-way
//! never exposes a partial file, and systemd treats a SIGTERM exit as clean.

use crate::herdr::Herdr;
use crate::report::{collect_rows, Row};
use chrono::{DateTime, SecondsFormat, Utc};
use serde::Serialize;
use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::Path;
use std::process;
use std::thread;
use std::time::Duration;

pub const DEFAULT_INTERVAL_SECS: u64 = 30;
pub const DEFAULT_THRESHOLDS: [u32; 3] = [50, 60, 80];

const AGENTS_FILE: &str = "agents.json";
const STATE_FILE: &str = "notify_state.json";

/// pane id ごとの「今いる段」。知らせ済みの閾値のうち、今の pct 以下で最大のもの。
/// The level each pane sits at: the highest notified threshold not above the current pct.
pub type NotifyState = BTreeMap<String, u32>;

#[derive(Debug, Clone, PartialEq)]
pub struct WatchOptions {
  pub interval: Duration,
  pub thresholds: Vec<u32>,
}

#[derive(Debug, PartialEq)]
pub struct Notice {
  pub pane_id: String,
  pub title: String,
  pub body: String,
}

#[derive(Serialize)]
struct AgentsFile<'a> {
  generated_at: String,
  agents: &'a [Row],
}

pub fn parse_thresholds(text: &str) -> Result<Vec<u32>, String> {
  let mut thresholds = text
    .split(',')
    .map(|part| {
      part
        .trim()
        .parse::<u32>()
        .map_err(|_| format!("閾値を整数で読めない: {part}"))
    })
    .collect::<Result<Vec<u32>, String>>()?;
  thresholds.sort_unstable();
  thresholds.dedup();
  Ok(thresholds)
}

fn notice(row: &Row, pct: u32) -> Notice {
  let label = row.name.as_deref().unwrap_or(&row.pane_id);
  let place = row
    .cwd
    .as_deref()
    .and_then(|cwd| Path::new(cwd).file_name())
    .map_or_else(
      || "?".to_string(),
      |name| name.to_string_lossy().into_owned(),
    );
  let status = row.agent_status.as_deref().unwrap_or("?");
  Notice {
    pane_id: row.pane_id.clone(),
    title: format!("{label} context {pct}%"),
    body: format!("{place} / {status}"),
  }
}

/// 次の状態と、今回出す通知を決める。一度に複数の閾値を跨いでも通知は 1 回にする。
/// 下がったときは段を今の pct まで下げるだけで知らせない。記録を丸ごと消すと、上に跨いでいない
/// 下の閾値を次の周期で知らせてしまう。一覧に無い agent は next に写らないので、記録が消える。
/// Decides the next state and this tick's notices. Crossing several thresholds at once yields one
/// notice. Going down only lowers the level silently: wiping the record would announce a lower
/// threshold that was never crossed upward. Agents absent from rows simply drop out of next.
pub fn plan(prev: &NotifyState, rows: &[Row], thresholds: &[u32]) -> (NotifyState, Vec<Notice>) {
  let mut next = NotifyState::new();
  let mut notices = Vec::new();
  for row in rows {
    let last = prev.get(&row.pane_id).copied();
    let Some(pct) = row.pct else {
      // /compact の直後などは値が null になる。情報が無いだけなので記録は保つ
      // pct is null right after /compact and the like: no information, so keep the record
      if let Some(level) = last {
        next.insert(row.pane_id.clone(), level);
      }
      continue;
    };
    let Some(level) = thresholds.iter().copied().filter(|t| *t <= pct).max() else {
      continue;
    };
    next.insert(row.pane_id.clone(), level);
    if last.is_none_or(|last| level > last) {
      notices.push(notice(row, pct));
    }
  }
  (next, notices)
}

/// 同じディレクトリの一時ファイルに書いて置き換える。読む側に途中の状態を見せない。
/// Writes to a temp file in the same directory, then replaces, so readers never see a partial file.
fn write_atomic(path: &Path, content: &str) -> io::Result<()> {
  let mut tmp = path.as_os_str().to_owned();
  tmp.push(format!(".tmp.{}", process::id()));
  fs::write(&tmp, content)?;
  fs::rename(&tmp, path).inspect_err(|_| {
    let _ = fs::remove_file(&tmp);
  })
}

fn write_agents(ctx_dir: &Path, rows: &[Row], now: DateTime<Utc>) -> Result<(), String> {
  let file = AgentsFile {
    generated_at: now.to_rfc3339_opts(SecondsFormat::Secs, true),
    agents: rows,
  };
  let text = serde_json::to_string_pretty(&file).map_err(|e| format!("JSON を書けない: {e}"))?;
  fs::create_dir_all(ctx_dir).map_err(|e| format!("{} を作れない: {e}", ctx_dir.display()))?;
  write_atomic(&ctx_dir.join(AGENTS_FILE), &(text + "\n"))
    .map_err(|e| format!("{AGENTS_FILE} を書けない: {e}"))
}

fn load_state(ctx_dir: &Path) -> NotifyState {
  let path = ctx_dir.join(STATE_FILE);
  let Ok(text) = fs::read_to_string(&path) else {
    return NotifyState::new();
  };
  serde_json::from_str(&text).unwrap_or_else(|e| {
    eprintln!("herdr-ctx: {STATE_FILE} を読めないので空から始める: {e}");
    NotifyState::new()
  })
}

fn save_state(ctx_dir: &Path, state: &NotifyState) -> Result<(), String> {
  let text = serde_json::to_string(state).map_err(|e| format!("JSON を書けない: {e}"))?;
  write_atomic(&ctx_dir.join(STATE_FILE), &(text + "\n"))
    .map_err(|e| format!("{STATE_FILE} を書けない: {e}"))
}

/// 1 周期ぶんの処理。herdr に繋がらなければ stderr に 1 行書くだけで、状態を変えない。
/// One cycle. If herdr is unreachable it writes one stderr line and leaves the state alone.
pub fn tick(
  herdr: &dyn Herdr,
  ctx_dir: &Path,
  thresholds: &[u32],
  state: &mut NotifyState,
  now: DateTime<Utc>,
) {
  let rows = match collect_rows(herdr, &ctx_dir.join("panes"), now) {
    Ok(rows) => rows,
    Err(reason) => {
      eprintln!("herdr-ctx: {reason}");
      return;
    }
  };
  if let Err(reason) = write_agents(ctx_dir, &rows, now) {
    eprintln!("herdr-ctx: {reason}");
  }

  let (mut next, notices) = plan(state, &rows, thresholds);
  for notice in notices {
    if let Err(reason) = herdr.notify(&notice.title, &notice.body) {
      eprintln!("herdr-ctx: 通知できない: {reason}");
      // 届かなかった通知は知らせた扱いにせず、次の周期でもう一度試す
      // An undelivered notice does not count, so the next cycle tries again
      match state.get(&notice.pane_id) {
        Some(level) => next.insert(notice.pane_id, *level),
        None => next.remove(&notice.pane_id),
      };
    }
  }

  if next != *state {
    if let Err(reason) = save_state(ctx_dir, &next) {
      eprintln!("herdr-ctx: {reason}");
    }
    *state = next;
  }
}

pub fn run(herdr: &dyn Herdr, ctx_dir: &Path, options: &WatchOptions) -> ! {
  let mut state = load_state(ctx_dir);
  loop {
    tick(herdr, ctx_dir, &options.thresholds, &mut state, Utc::now());
    thread::sleep(options.interval);
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::testutil::{temp_dir, FakeHerdr, AGENT_LIST_JSON};

  const THRESHOLDS: [u32; 3] = [50, 60, 80];

  fn row(pct: Option<u32>) -> Row {
    Row {
      name: Some("worker-a".to_string()),
      pane_id: "w1:p1".to_string(),
      agent_status: Some("working".to_string()),
      cwd: Some("/home/archie/dotfiles".to_string()),
      pct,
      ctx_tokens: None,
      context_window_size: None,
      model: None,
      last_turn_at: None,
      stale: false,
      note: None,
    }
  }

  /// pct の列を流して、周期ごとの通知の件数を返す。
  /// Feeds a sequence of pct values and returns the notice count per cycle.
  fn counts(sequence: &[Option<u32>]) -> Vec<usize> {
    let mut state = NotifyState::new();
    sequence
      .iter()
      .map(|pct| {
        let (next, notices) = plan(&state, &[row(*pct)], &THRESHOLDS);
        state = next;
        notices.len()
      })
      .collect()
  }

  #[test]
  fn crossing_upward_notifies_once() {
    assert_eq!(
      counts(&[Some(49), Some(50), Some(55), Some(59)]),
      [0, 1, 0, 0]
    );
  }

  #[test]
  fn each_threshold_notifies_on_its_own() {
    assert_eq!(counts(&[Some(50), Some(60), Some(80)]), [1, 1, 1]);
  }

  #[test]
  fn jumping_over_several_thresholds_notifies_once() {
    assert_eq!(counts(&[Some(45), Some(85), Some(86)]), [0, 1, 0]);
  }

  #[test]
  fn the_first_sighting_above_a_threshold_notifies() {
    assert_eq!(counts(&[Some(62), Some(62)]), [1, 0]);
  }

  #[test]
  fn dropping_within_the_thresholds_does_not_announce_the_lower_one() {
    assert_eq!(counts(&[Some(62), Some(55)]), [1, 0]);
  }

  #[test]
  fn crossing_again_after_dropping_notifies_again() {
    assert_eq!(counts(&[Some(62), Some(55), Some(61)]), [1, 0, 1]);
  }

  #[test]
  fn dropping_below_every_threshold_clears_the_record() {
    let (state, _) = plan(&NotifyState::new(), &[row(Some(62))], &THRESHOLDS);
    let (state, notices) = plan(&state, &[row(Some(10))], &THRESHOLDS);
    assert!(state.is_empty());
    assert!(notices.is_empty());
    assert_eq!(counts(&[Some(62), Some(10), Some(52)]), [1, 0, 1]);
  }

  #[test]
  fn a_vanished_agent_loses_its_record() {
    let (state, _) = plan(&NotifyState::new(), &[row(Some(62))], &THRESHOLDS);
    let (state, notices) = plan(&state, &[], &THRESHOLDS);
    assert!(state.is_empty());
    assert!(notices.is_empty());

    let (_, notices) = plan(&state, &[row(Some(62))], &THRESHOLDS);
    assert_eq!(notices.len(), 1);
  }

  #[test]
  fn a_null_pct_keeps_the_record() {
    assert_eq!(counts(&[Some(62), None, Some(63)]), [1, 0, 0]);
  }

  #[test]
  fn the_notice_uses_the_name_and_the_cwd_basename() {
    let (_, notices) = plan(&NotifyState::new(), &[row(Some(62))], &THRESHOLDS);
    assert_eq!(notices[0].title, "worker-a context 62%");
    assert_eq!(notices[0].body, "dotfiles / working");
  }

  #[test]
  fn the_notice_falls_back_to_the_pane_id() {
    let mut unnamed = row(Some(62));
    unnamed.name = None;
    let (_, notices) = plan(&NotifyState::new(), &[unnamed], &THRESHOLDS);
    assert_eq!(notices[0].title, "w1:p1 context 62%");
  }

  #[test]
  fn thresholds_are_parsed_sorted_and_deduplicated() {
    assert_eq!(parse_thresholds("80, 50,60,50").unwrap(), [50, 60, 80]);
    assert!(parse_thresholds("50,x").is_err());
    assert!(parse_thresholds("").is_err());
  }

  fn write_pane(ctx_dir: &Path, pct: u32) {
    let panes = ctx_dir.join("panes");
    fs::create_dir_all(&panes).unwrap();
    let text = format!(r#"{{"used_percentage":{pct},"updated_at":"2026-11-05T12:34:56Z"}}"#);
    fs::write(panes.join("w3C_p1W.json"), text).unwrap();
  }

  fn now() -> DateTime<Utc> {
    DateTime::parse_from_rfc3339("2026-11-05T12:35:00Z")
      .unwrap()
      .with_timezone(&Utc)
  }

  #[test]
  fn tick_writes_agents_json_and_notifies_only_once() {
    let dir = temp_dir("tick");
    write_pane(&dir, 62);
    let herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    let mut state = NotifyState::new();

    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());
    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());

    let notified = herdr.notified.borrow();
    assert_eq!(notified.len(), 1);
    assert_eq!(notified[0].0, "commander-dotfiles context 62%");
    assert_eq!(notified[0].1, "dotfiles / working");

    let text = fs::read_to_string(dir.join(AGENTS_FILE)).unwrap();
    let file: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(file["generated_at"], "2026-11-05T12:35:00Z");
    assert_eq!(file["agents"].as_array().unwrap().len(), 2);
    assert_eq!(file["agents"][0]["pct"], 62);
  }

  #[test]
  fn the_state_survives_a_restart() {
    let dir = temp_dir("restart");
    write_pane(&dir, 62);
    let herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    let mut state = NotifyState::new();
    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());

    let mut restarted = load_state(&dir);
    assert_eq!(restarted, state);
    tick(&herdr, &dir, &THRESHOLDS, &mut restarted, now());
    assert_eq!(herdr.notified.borrow().len(), 1);
  }

  #[test]
  fn a_failed_notice_is_retried_on_the_next_tick() {
    let dir = temp_dir("retry");
    write_pane(&dir, 62);
    let mut herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    herdr.notify_result = Err("no server".to_string());
    let mut state = NotifyState::new();

    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());
    assert!(state.is_empty());

    herdr.notify_result = Ok(());
    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());
    assert_eq!(state.get("w3C:p1W"), Some(&60));
  }

  #[test]
  fn an_unreachable_herdr_keeps_the_state_and_writes_nothing() {
    let dir = temp_dir("unreachable");
    let mut herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    herdr.list = Err("no herdr server is running".to_string());
    let mut state = NotifyState::from([("w3C:p1W".to_string(), 60)]);

    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());

    assert_eq!(state.get("w3C:p1W"), Some(&60));
    assert!(!dir.join(AGENTS_FILE).exists());
  }

  #[test]
  fn a_broken_state_file_starts_empty() {
    let dir = temp_dir("broken-state");
    fs::write(dir.join(STATE_FILE), "{broken").unwrap();
    assert!(load_state(&dir).is_empty());
  }

  #[test]
  fn write_atomic_leaves_no_temp_file() {
    let dir = temp_dir("atomic");
    write_atomic(&dir.join("a.json"), "{}\n").unwrap();
    let names: Vec<_> = fs::read_dir(&dir)
      .unwrap()
      .map(|e| e.unwrap().file_name())
      .collect();
    assert_eq!(names, ["a.json"]);
  }
}
