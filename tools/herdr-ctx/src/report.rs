//! agent と sidecar を結合して、list と self の出力を組み立てる。
//! Joins agents with sidecars and builds the output of list and self.

use crate::herdr::{get_agent, list_agents, Agent, Herdr};
use crate::sidecar::{read_sidecar, SidecarRead};
use chrono::{DateTime, Duration, TimeZone, Utc};
use serde::Serialize;
use std::fmt::Display;
use std::path::Path;

/// updated_at がこれより古い sidecar には stale を付ける。statusline はイベントでしか走らないので、
/// 待機中の agent も stale になる。stale は「値が古いかもしれない」印で、値が誤りという意味ではない。
/// Sidecars older than this are marked stale. The statusline only runs on events, so idle agents
/// go stale too: it means "may be old", not "wrong".
const STALE_AFTER_MINUTES: i64 = 10;

const COMMANDER_PREFIX: &str = "commander-";
const COMMANDER_LIMIT: u32 = 60;
const WORKER_LIMIT: u32 = 50;
const COMMANDER_ADVICE: &str = "context が 60% を超えた。次の worker の報告の節目で /wtclose を呼び、新しいセッション(commander-<repo>-2)に交代する(Issue #784 の交代の規則)";
const WORKER_ADVICE: &str =
  "context が 50% を超えた。差し戻しのラウンドを受ける前に司令塔へ引き継ぎの準備を相談する";

/// list の 1 行。鍵の順はこの宣言の順で、値が無い鍵も null で出す。
/// One list line. Keys follow this declaration order, and absent values are emitted as null.
#[derive(Debug, Clone, Serialize)]
pub struct Row {
  pub name: Option<String>,
  pub pane_id: String,
  pub agent_status: Option<String>,
  pub cwd: Option<String>,
  pub pct: Option<u32>,
  pub ctx_tokens: Option<u64>,
  pub context_window_size: Option<u64>,
  pub model: Option<String>,
  pub last_turn_at: Option<String>,
  pub stale: bool,
  pub note: Option<String>,
  /// 通知の記録の持ち主を見分けるために watch が使う。list の出力の鍵には含めない。
  /// Used by watch to tell whose notification record this is; not part of the list output.
  #[serde(skip)]
  pub session_id: Option<String>,
}

fn is_stale(updated_at: Option<&str>, now: DateTime<Utc>) -> bool {
  match updated_at.and_then(|text| DateTime::parse_from_rfc3339(text).ok()) {
    Some(time) => {
      now.signed_duration_since(time.with_timezone(&Utc)) > Duration::minutes(STALE_AFTER_MINUTES)
    }
    // 時刻が読めない値は新しいと言えないので、古い側に倒す
    // A value without a readable time cannot be called fresh
    None => true,
  }
}

pub fn join(agent: &Agent, sidecar: &SidecarRead, now: DateTime<Utc>) -> Row {
  let mut row = Row {
    name: agent.name.clone(),
    pane_id: agent.pane_id.clone(),
    agent_status: agent.agent_status.clone(),
    cwd: agent.cwd.clone(),
    pct: None,
    ctx_tokens: None,
    context_window_size: None,
    model: None,
    last_turn_at: None,
    stale: false,
    note: None,
    session_id: None,
  };
  // pane には前の Claude の sidecar が残っていることがある。stale は古さしか示さないので、
  // 持ち主が違う agent に結合すると、別の使用率とモデルを報告してしまう
  // A pane can hold a sidecar left by an earlier Claude. stale only tells age, so joining it to
  // another kind of agent would report someone else's usage and model
  if !agent.is_claude() {
    row.note = Some("not a claude agent".to_string());
    return row;
  }
  match sidecar {
    SidecarRead::Found(sidecar) => {
      row.session_id = sidecar.session_id.clone();
      row.pct = sidecar.pct();
      row.ctx_tokens = sidecar.total_input_tokens;
      row.context_window_size = sidecar.context_window_size;
      row.model = sidecar.model().map(str::to_string);
      row.last_turn_at = sidecar.updated_at.clone();
      row.stale = is_stale(sidecar.updated_at.as_deref(), now);
    }
    SidecarRead::Missing => row.note = Some("no sidecar".to_string()),
    SidecarRead::Unreadable => row.note = Some("unreadable sidecar".to_string()),
  }
  row
}

pub fn collect_rows(
  herdr: &dyn Herdr,
  panes_dir: &Path,
  now: DateTime<Utc>,
) -> Result<Vec<Row>, String> {
  let agents = list_agents(herdr)?;
  Ok(
    agents
      .iter()
      .map(|agent| join(agent, &read_sidecar(panes_dir, &agent.pane_id), now))
      .collect(),
  )
}

pub fn json_lines(rows: &[Row]) -> Result<String, String> {
  let mut text = String::new();
  for row in rows {
    let line = serde_json::to_string(row).map_err(|e| format!("JSON を書けない: {e}"))?;
    text.push_str(&line);
    text.push('\n');
  }
  Ok(text)
}

fn clock<Tz: TimeZone>(updated_at: &str, tz: &Tz) -> Option<String>
where
  Tz::Offset: Display,
{
  let time = DateTime::parse_from_rfc3339(updated_at).ok()?;
  Some(time.with_timezone(tz).format("%H:%M").to_string())
}

/// 人が読む表。名前の無い agent は pane id で見分ける。
/// A table for people. Unnamed agents are identified by their pane id.
pub fn table<Tz: TimeZone>(rows: &[Row], tz: &Tz) -> String
where
  Tz::Offset: Display,
{
  let mut lines = vec![["NAME", "STATUS", "PCT", "UPDATED"].map(str::to_string)];
  for row in rows {
    let updated = row
      .last_turn_at
      .as_deref()
      .and_then(|text| clock(text, tz))
      .unwrap_or_else(|| "-".to_string());
    lines.push([
      row.name.clone().unwrap_or_else(|| row.pane_id.clone()),
      row.agent_status.clone().unwrap_or_else(|| "-".to_string()),
      row
        .pct
        .map_or_else(|| "-".to_string(), |pct| format!("{pct}%")),
      if row.stale {
        format!("{updated} (stale)")
      } else {
        updated
      },
    ]);
  }

  let mut widths = [0; 4];
  for line in &lines {
    for (width, cell) in widths.iter_mut().zip(line) {
      *width = (*width).max(cell.chars().count());
    }
  }

  let mut text = String::new();
  for line in &lines {
    let cells: Vec<String> = line
      .iter()
      .zip(widths)
      .map(|(cell, width)| format!("{cell:<width$}"))
      .collect();
    text.push_str(cells.join("  ").trim_end());
    text.push('\n');
  }
  text
}

fn advice(name: Option<&str>, pct: u32) -> Option<&'static str> {
  let is_commander = name.is_some_and(|name| name.starts_with(COMMANDER_PREFIX));
  if is_commander {
    (pct >= COMMANDER_LIMIT).then_some(COMMANDER_ADVICE)
  } else {
    (pct >= WORKER_LIMIT).then_some(WORKER_ADVICE)
  }
}

/// self の出力。None は「何も出さない」を表す。hook の主の価値は 1 行目の使用率で、助言は従なので、
/// 役割を読むための herdr が失敗しても 1 行目は出し、助言だけを省いて理由を stderr に書く。
/// Output of self; None means print nothing. The hook's main value is the usage line and advice is
/// secondary, so a herdr failure while reading the role keeps the line and only drops the advice.
pub fn self_report<Tz: TimeZone>(
  herdr: &dyn Herdr,
  panes_dir: &Path,
  pane_id: Option<&str>,
  tz: &Tz,
) -> Option<String>
where
  Tz::Offset: Display,
{
  let pane_id = pane_id?;
  let SidecarRead::Found(sidecar) = read_sidecar(panes_dir, pane_id) else {
    return None;
  };
  let pct = sidecar.pct()?;

  let model = sidecar.model().unwrap_or("?");
  let as_of = sidecar
    .updated_at
    .as_deref()
    .and_then(|text| clock(text, tz))
    .unwrap_or_else(|| "?".to_string());
  let mut text = format!("context {pct}% (pane {pane_id}, model {model}, as of {as_of})\n");

  // 役割が要るのは助言を足す可能性があるときだけ。hook は毎ターン走るので、下回る間は herdr を呼ばない
  // The role only matters when advice may follow. The hook runs every turn, so skip herdr below it
  if pct >= WORKER_LIMIT.min(COMMANDER_LIMIT) {
    match get_agent(herdr, pane_id) {
      Ok(agent) => {
        if let Some(line) = advice(agent.name.as_deref(), pct) {
          text.push_str(line);
          text.push('\n');
        }
      }
      Err(reason) => eprintln!("herdr-ctx: {reason}"),
    }
  }
  Some(text)
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::sidecar::{sidecar_path, Sidecar};
  use crate::testutil::{temp_dir, FakeHerdr, AGENT_GET_JSON, AGENT_LIST_JSON};
  use std::fs;

  fn now() -> DateTime<Utc> {
    DateTime::parse_from_rfc3339("2026-11-05T12:40:00Z")
      .unwrap()
      .with_timezone(&Utc)
  }

  fn agent() -> Agent {
    Agent {
      pane_id: "w3C:p1W".to_string(),
      agent: Some("claude".to_string()),
      name: Some("commander-dotfiles".to_string()),
      agent_status: Some("working".to_string()),
      cwd: Some("/home/archie/dotfiles".to_string()),
    }
  }

  fn sidecar(updated_at: &str) -> Sidecar {
    Sidecar {
      session_id: Some("session-a".to_string()),
      used_percentage: Some(62.0),
      context_window_size: Some(1_000_000),
      total_input_tokens: Some(620_000),
      model_id: Some("claude-fable-5-1".to_string()),
      model_name: Some("Fable 5.1".to_string()),
      updated_at: Some(updated_at.to_string()),
    }
  }

  fn write_sidecar(dir: &Path, pane_id: &str, pct: u32) {
    let text = format!(
      r#"{{"pane_id":"{pane_id}","used_percentage":{pct},"model_name":"Fable 5.1","updated_at":"2026-11-05T12:34:56Z"}}"#
    );
    fs::write(sidecar_path(dir, pane_id), text).unwrap();
  }

  #[test]
  fn join_without_a_sidecar_keeps_the_agent_with_a_note() {
    let row = join(&agent(), &SidecarRead::Missing, now());
    assert_eq!(row.name.as_deref(), Some("commander-dotfiles"));
    assert_eq!(row.pct, None);
    assert_eq!(row.note.as_deref(), Some("no sidecar"));
    assert!(!row.stale);
  }

  #[test]
  fn join_with_an_unreadable_sidecar_keeps_the_agent_with_a_note() {
    let row = join(&agent(), &SidecarRead::Unreadable, now());
    assert_eq!(row.pct, None);
    assert_eq!(row.note.as_deref(), Some("unreadable sidecar"));
  }

  #[test]
  fn join_does_not_attach_a_leftover_sidecar_to_another_kind_of_agent() {
    let mut copilot = agent();
    copilot.agent = Some("copilot".to_string());
    let found = SidecarRead::Found(sidecar("2026-11-05T12:34:56Z"));
    let row = join(&copilot, &found, now());
    assert_eq!(row.name.as_deref(), Some("commander-dotfiles"));
    assert_eq!(row.pct, None);
    assert_eq!(row.ctx_tokens, None);
    assert_eq!(row.context_window_size, None);
    assert_eq!(row.model, None);
    assert_eq!(row.last_turn_at, None);
    assert_eq!(row.session_id, None);
    assert!(!row.stale);
    assert_eq!(row.note.as_deref(), Some("not a claude agent"));
  }

  #[test]
  fn join_fills_the_row_from_a_fresh_sidecar() {
    let found = SidecarRead::Found(sidecar("2026-11-05T12:34:56Z"));
    let row = join(&agent(), &found, now());
    assert_eq!(row.pct, Some(62));
    assert_eq!(row.ctx_tokens, Some(620_000));
    assert_eq!(row.context_window_size, Some(1_000_000));
    assert_eq!(row.model.as_deref(), Some("Fable 5.1"));
    assert_eq!(row.last_turn_at.as_deref(), Some("2026-11-05T12:34:56Z"));
    assert_eq!(row.session_id.as_deref(), Some("session-a"));
    assert!(!row.stale);
    assert_eq!(row.note, None);
  }

  #[test]
  fn join_marks_an_old_sidecar_stale_but_keeps_the_value() {
    let found = SidecarRead::Found(sidecar("2026-11-05T12:29:59Z"));
    let row = join(&agent(), &found, now());
    assert!(row.stale);
    assert_eq!(row.pct, Some(62));
  }

  #[test]
  fn exactly_ten_minutes_is_not_stale_yet() {
    assert!(!is_stale(Some("2026-11-05T12:30:00Z"), now()));
  }

  #[test]
  fn an_unreadable_time_counts_as_stale() {
    assert!(is_stale(Some("yesterday"), now()));
    assert!(is_stale(None, now()));
  }

  #[test]
  fn json_lines_has_one_object_per_agent_with_every_key() {
    let dir = temp_dir("json-lines");
    write_sidecar(&dir, "w3C:p1W", 62);
    write_sidecar(&dir, "w3U:p1", 70);
    let rows = collect_rows(&FakeHerdr::with_list(AGENT_LIST_JSON), &dir, now()).unwrap();
    let text = json_lines(&rows).unwrap();

    let lines: Vec<&str> = text.lines().collect();
    assert_eq!(lines.len(), 3);

    let first: serde_json::Value = serde_json::from_str(lines[0]).unwrap();
    assert_eq!(first["name"], "commander-dotfiles");
    assert_eq!(first["pct"], 62);
    assert_eq!(first["stale"], false);
    assert!(first["note"].is_null());

    let second: serde_json::Value = serde_json::from_str(lines[1]).unwrap();
    assert!(second["name"].is_null());
    assert!(second["pct"].is_null());
    assert_eq!(second["note"], "no sidecar");

    let third: serde_json::Value = serde_json::from_str(lines[2]).unwrap();
    assert!(third["pct"].is_null());
    assert_eq!(third["note"], "not a claude agent");

    let keys = [
      "name",
      "pane_id",
      "agent_status",
      "cwd",
      "pct",
      "ctx_tokens",
      "context_window_size",
      "model",
      "last_turn_at",
      "stale",
      "note",
    ];
    let object = second.as_object().unwrap();
    assert_eq!(object.len(), keys.len());
    for key in keys {
      assert!(object.contains_key(key), "{key}");
    }
  }

  #[test]
  fn table_shows_name_status_pct_and_time() {
    let found = SidecarRead::Found(sidecar("2026-11-05T12:34:56Z"));
    let mut unnamed = agent();
    unnamed.name = None;
    let rows = vec![
      join(&agent(), &found, now()),
      join(&unnamed, &SidecarRead::Missing, now()),
    ];
    let text = table(&rows, &Utc);
    let lines: Vec<&str> = text.lines().collect();
    assert_eq!(lines[0], "NAME                STATUS   PCT  UPDATED");
    assert_eq!(lines[1], "commander-dotfiles  working  62%  12:34");
    assert_eq!(lines[2], "w3C:p1W             working  -    -");
  }

  #[test]
  fn table_flags_stale_rows() {
    let found = SidecarRead::Found(sidecar("2026-11-05T12:00:00Z"));
    let text = table(&[join(&agent(), &found, now())], &Utc);
    assert!(text.contains("12:00 (stale)"), "{text}");
  }

  #[test]
  fn self_is_silent_without_a_pane_or_a_usable_sidecar() {
    let dir = temp_dir("self-silent");
    let herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    assert_eq!(self_report(&herdr, &dir, None, &Utc), None);
    assert_eq!(self_report(&herdr, &dir, Some("w1:p1"), &Utc), None);

    fs::write(sidecar_path(&dir, "w1:p1"), "{broken").unwrap();
    assert_eq!(self_report(&herdr, &dir, Some("w1:p1"), &Utc), None);

    fs::write(sidecar_path(&dir, "w1:p1"), r#"{"used_percentage":null}"#).unwrap();
    assert_eq!(self_report(&herdr, &dir, Some("w1:p1"), &Utc), None);
  }

  #[test]
  fn self_prints_one_line_below_the_limit_without_calling_herdr() {
    let dir = temp_dir("self-line");
    write_sidecar(&dir, "w3C:p1W", 49);
    let mut herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    herdr.get = Err("must not be called".to_string());
    let text = self_report(&herdr, &dir, Some("w3C:p1W"), &Utc).unwrap();
    assert_eq!(
      text,
      "context 49% (pane w3C:p1W, model Fable 5.1, as of 12:34)\n"
    );
  }

  fn report_for(name: &str, pct: u32) -> String {
    let dir = temp_dir(&format!("self-{name}-{pct}"));
    write_sidecar(&dir, "w3C:p1W", pct);
    let mut herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    herdr.get = Ok(AGENT_GET_JSON.replace("commander-dotfiles", name));
    self_report(&herdr, &dir, Some("w3C:p1W"), &Utc).unwrap()
  }

  #[test]
  fn commander_gets_the_handover_line_from_sixty() {
    assert_eq!(report_for("commander-dotfiles", 59).lines().count(), 1);
    let text = report_for("commander-dotfiles", 60);
    assert_eq!(text.lines().nth(1), Some(COMMANDER_ADVICE));
  }

  #[test]
  fn worker_gets_the_consult_line_from_fifty() {
    let text = report_for("claude-herdr-ctx-gauge", 50);
    assert_eq!(text.lines().nth(1), Some(WORKER_ADVICE));
  }

  #[test]
  fn an_unnamed_agent_counts_as_a_worker() {
    assert_eq!(advice(None, 50), Some(WORKER_ADVICE));
    assert_eq!(advice(None, 49), None);
  }

  #[test]
  fn self_keeps_the_usage_line_when_herdr_fails_above_the_limit() {
    let dir = temp_dir("self-herdr-fails");
    write_sidecar(&dir, "w3C:p1W", 62);
    let mut herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    herdr.get = Err("no herdr server is running".to_string());
    let text = self_report(&herdr, &dir, Some("w3C:p1W"), &Utc).unwrap();
    assert_eq!(
      text,
      "context 62% (pane w3C:p1W, model Fable 5.1, as of 12:34)\n"
    );
  }
}
