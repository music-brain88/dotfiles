//! 常駐のループ。スレッドを 2 本持つ。主スレッドは agents.json を書き、閾値を下から上に跨いだ agent を
//! 1 回だけ知らせる。もう 1 本は別の周期でレビュー依頼を集めて reviews.json を書く。2 本は状態を共有せず、
//! 書くファイルも別なので、gh の遅さと失敗は agent の周期に届かない。
//! SIGTERM は既定の動作のままにする。書き込みは一時ファイル + rename なので、途中で落ちても
//! 読む側に書きかけのファイルは見えず、systemd は SIGTERM での終了を正常終了として扱う。
//! The resident loop, on two threads. The main one writes agents.json and notifies once per upward
//! threshold crossing; the other gathers review requests on its own period into reviews.json. They
//! share no state and write different files, so gh's slowness and failures never reach the agent
//! cycle.
//! SIGTERM keeps its default action. Writes go through a temp file and rename, so dying mid-way
//! never exposes a partial file, and systemd treats a SIGTERM exit as clean.

use crate::github::{fetch_reviews, GitHub};
use crate::herdr::{show_notification, Herdr};
use crate::keyring::{Keyring, KeyringState};
use crate::report::{collect_rows, Row};
use chrono::{DateTime, SecondsFormat, Utc};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::panic::{self, AssertUnwindSafe};
use std::path::{Path, PathBuf};
use std::process;
use std::thread;
use std::time::Duration;

pub const DEFAULT_INTERVAL_SECS: u64 = 30;
pub const DEFAULT_THRESHOLDS: [u32; 3] = [50, 60, 80];
pub const DEFAULT_REVIEWS_INTERVAL_SECS: u64 = 300;

const AGENTS_FILE: &str = "agents.json";
const STATE_FILE: &str = "notify_state.json";
const REVIEWS_FILE: &str = "reviews.json";

/// 所有者だけが読み書きできる権限。reviews.json は非公開のリポジトリの名前と PR の題を含みうるので、
/// 同じ機械の他のユーザーに読ませない。
/// Owner-only read and write. reviews.json may hold private repository names and PR titles, so
/// other users on the same machine must not read it.
const PRIVATE_MODE: u32 = 0o600;

/// pane の「今いる段」と、その段を知らせた session。段は、知らせ済みの閾値のうち今の pct 以下で最大のもの。
/// pane id は場所しか示さないので、session_id で記録の持ち主を見分ける。
/// A pane's level and the session it was announced for. The level is the highest notified threshold
/// not above the current pct. A pane id only names a place, so session_id tells whose record it is.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Notified {
  pub threshold: u32,
  pub session_id: Option<String>,
}

pub type NotifyState = BTreeMap<String, Notified>;

/// メモリ上の記録と、最後にファイルへ保存できた記録。分けて持つと、保存の失敗中も通知を繰り返さず、
/// 次の周期で保存を再試行できる。
/// The in-memory record and the last one saved to disk. Keeping both means a failed save neither
/// repeats notifications nor loses the retry on the next cycle.
#[derive(Debug, Default)]
pub struct WatchState {
  current: NotifyState,
  saved: NotifyState,
}

impl WatchState {
  fn load(ctx_dir: &Path) -> Self {
    let state = load_state(ctx_dir);
    Self {
      current: state.clone(),
      saved: state,
    }
  }
}

#[derive(Debug, Clone, PartialEq)]
pub struct WatchOptions {
  pub interval: Duration,
  pub thresholds: Vec<u32>,
  pub reviews_interval: Duration,
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
///
/// session_id が変わった pane は、前の記録を無いものとして判定する。前の session が 80% で知らせた
/// pane で別の session が 62% から始まっても、新しい session の閾値を知らせるため。
/// A pane whose session_id changed is judged as if it had no record, so a new session starting at
/// 62% in a pane notified at 80% by an earlier session still gets its own notice.
pub fn plan(prev: &NotifyState, rows: &[Row], thresholds: &[u32]) -> (NotifyState, Vec<Notice>) {
  let mut next = NotifyState::new();
  let mut notices = Vec::new();
  for row in rows {
    // 別の session の値かもしれない行では判断しない。通知を出さず、記録も動かさない
    // A row that may hold another session's value decides nothing: no notice, no record change
    if row.session_match == Some(false) {
      if let Some(record) = prev.get(&row.pane_id) {
        next.insert(row.pane_id.clone(), record.clone());
      }
      continue;
    }
    let last = prev
      .get(&row.pane_id)
      .filter(|record| record.session_id == row.session_id);
    let Some(pct) = row.pct else {
      // /compact の直後などは値が null になる。同じ session なら情報が無いだけなので記録は保つ
      // pct is null right after /compact and the like: within a session that is merely no
      // information, so keep the record
      if let Some(record) = last {
        next.insert(row.pane_id.clone(), record.clone());
      }
      continue;
    };
    let Some(level) = thresholds.iter().copied().filter(|t| *t <= pct).max() else {
      continue;
    };
    next.insert(
      row.pane_id.clone(),
      Notified {
        threshold: level,
        session_id: row.session_id.clone(),
      },
    );
    if last.is_none_or(|record| level > record.threshold) {
      notices.push(notice(row, pct));
    }
  }
  (next, notices)
}

/// 同じディレクトリの一時ファイルに書いて置き換える。読む側に途中の状態を見せない。
/// 一時ファイルの名前は置き換え先の名前を含むので、2 本のスレッドが別のファイルを同時に書いてもぶつからない。
/// Writes to a temp file in the same directory, then replaces, so readers never see a partial file.
/// The temp name includes the target's name, so the two threads writing different files never clash.
fn write_atomic(path: &Path, content: &str) -> io::Result<()> {
  let tmp = temp_path(path);
  fs::write(&tmp, content)?;
  replace(&tmp, path)
}

/// write_atomic と同じく置き換えるが、一時ファイルを作る時点で所有者だけが読み書きできる権限にする。
/// 書いてから chmod すると、その間に他のユーザーが中身を読める。rename は一時ファイルの権限を持ち込むので、
/// 置き換える前のファイルが 0644 でも、置き換えた後は 0600 になる。
/// Replaces like write_atomic, but the temp file is owner-only from the moment it is created:
/// writing first and chmod-ing later would leave a window for other users to read it. rename
/// carries the temp file's mode over, so a 0644 destination becomes 0600 once replaced.
fn write_atomic_private(path: &Path, content: &str) -> io::Result<()> {
  let tmp = temp_path(path);
  // 前の周期が途中で落ちて残した一時ファイルは、別の権限を持つかもしれないので先に消す
  // A temp file left by a cycle that died mid-way may carry another mode, so remove it first
  match fs::remove_file(&tmp) {
    Err(e) if e.kind() != io::ErrorKind::NotFound => return Err(e),
    _ => {}
  }
  if let Err(e) = create_private(&tmp, content) {
    let _ = fs::remove_file(&tmp);
    return Err(e);
  }
  replace(&tmp, path)
}

/// create_new は既にあるパスを開かないので、権限は必ずここで作ったときの値になる。umask は作るときの権限を
/// 狭めることがあるので、開いた後にもう一度 0600 に揃える。
/// create_new never opens an existing path, so the mode is always the one set here. A umask can
/// narrow the mode at creation, so it is set to 0600 again once open.
fn create_private(tmp: &Path, content: &str) -> io::Result<()> {
  let mut file = OpenOptions::new()
    .write(true)
    .create_new(true)
    .mode(PRIVATE_MODE)
    .open(tmp)?;
  file.set_permissions(fs::Permissions::from_mode(PRIVATE_MODE))?;
  file.write_all(content.as_bytes())
}

fn temp_path(path: &Path) -> PathBuf {
  let mut tmp = path.as_os_str().to_owned();
  tmp.push(format!(".tmp.{}", process::id()));
  PathBuf::from(tmp)
}

fn replace(tmp: &Path, path: &Path) -> io::Result<()> {
  fs::rename(tmp, path).inspect_err(|_| {
    let _ = fs::remove_file(tmp);
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

/// 一覧を読んで agents.json を書き、通知を出して、次の記録を返す。
/// herdr に繋がらなければ stderr に 1 行書いて None を返す。
/// Reads the list, writes agents.json, sends notices and returns the next record.
/// If herdr is unreachable it writes one stderr line and returns None.
fn advance(
  herdr: &dyn Herdr,
  ctx_dir: &Path,
  thresholds: &[u32],
  prev: &NotifyState,
  now: DateTime<Utc>,
) -> Option<NotifyState> {
  let rows = match collect_rows(herdr, &ctx_dir.join("panes"), now) {
    Ok(rows) => rows,
    Err(reason) => {
      eprintln!("herdr-ctx: {reason}");
      return None;
    }
  };
  if let Err(reason) = write_agents(ctx_dir, &rows, now) {
    eprintln!("herdr-ctx: {reason}");
  }

  let (mut next, notices) = plan(prev, &rows, thresholds);
  for notice in notices {
    if let Err(reason) = show_notification(herdr, &notice.title, &notice.body) {
      eprintln!("herdr-ctx: 通知できない: {reason}");
      // 届かなかった通知は知らせた扱いにせず、次の周期でもう一度試す
      // An undelivered notice does not count, so the next cycle tries again
      match prev.get(&notice.pane_id) {
        Some(record) => next.insert(notice.pane_id, record.clone()),
        None => next.remove(&notice.pane_id),
      };
    }
  }
  Some(next)
}

/// 最後に保存できた記録と違う間は、周期ごとに保存を試みる。失敗してもメモリ上の記録は戻さない。
/// Tries to save on every cycle while the record differs from the last saved one. A failure never
/// rolls back the in-memory record.
fn persist(ctx_dir: &Path, state: &mut WatchState) {
  if state.current == state.saved {
    return;
  }
  match save_state(ctx_dir, &state.current) {
    Ok(()) => state.saved = state.current.clone(),
    Err(reason) => eprintln!("herdr-ctx: {reason}"),
  }
}

/// 1 周期ぶんの処理。herdr に繋がらない周期も、保存の再試行だけは行う。
/// One cycle. Even a cycle without herdr still retries a pending save.
pub fn tick(
  herdr: &dyn Herdr,
  ctx_dir: &Path,
  thresholds: &[u32],
  state: &mut WatchState,
  now: DateTime<Utc>,
) {
  if let Some(next) = advance(herdr, ctx_dir, thresholds, &state.current, now) {
    state.current = next;
  }
  persist(ctx_dir, state);
}

/// レビュー依頼の 1 周期。取得して reviews.json を所有者だけが読み書きできる権限で書く。
/// 取得・解釈・書き込みのどこかで失敗した周期は、
/// 前の reviews.json を残して理由を返す。空の一覧で上書きすると、読む側には「依頼が 0 件」に見えるため。
/// One review cycle: fetch and write reviews.json as owner-only. A cycle that fails anywhere (fetching, parsing,
/// writing) keeps the previous reviews.json and returns the reason, since an empty list would read
/// as "no requests".
pub fn refresh_reviews(
  github: &dyn GitHub,
  ctx_dir: &Path,
  now: DateTime<Utc>,
) -> Result<(), String> {
  let text = fetch_reviews(github, now)?.to_json()?;
  fs::create_dir_all(ctx_dir).map_err(|e| format!("{} を作れない: {e}", ctx_dir.display()))?;
  write_atomic_private(&ctx_dir.join(REVIEWS_FILE), &text)
    .map_err(|e| format!("{REVIEWS_FILE} を書けない: {e}"))
}

/// 鍵束の状態が変わった周期に、stderr に書く 1 行を返す。取得を見送り始めた周期と再開した周期だけが行を持つ。
/// 周期ごとに同じ行を書くと journal が埋まるため。
/// The stderr line for a change in the keyring's state. Only the cycle that starts skipping and the
/// one that resumes get a line; repeating it every cycle would flood the journal.
fn keyring_notice(last: KeyringState, current: KeyringState) -> Option<&'static str> {
  use KeyringState::{Locked, Unknown, Unlocked};
  match (last, current) {
    (Locked, Locked) => None,
    (_, Locked) => Some("鍵束がロックされているので、レビュー依頼の取得を見送る"),
    (Locked, Unlocked) => Some("鍵束が解錠されたので、レビュー依頼の取得を再開する"),
    (Locked, Unknown) => Some("鍵束の状態を確かめられないので、レビュー依頼の取得を再開する"),
    (Unlocked | Unknown, Unlocked | Unknown) => None,
  }
}

/// レビュー依頼のスレッドの 1 周期。stderr に書く行を返す。鍵束がロックされている周期は、gh を呼ばず
/// reviews.json も書き換えない。gh がトークンを読もうとして解錠を要求すると、画面の無い機械では
/// gnome-keyring-daemon が要求のたびに記述子を 1 個失い、やがて鍵束を開けなくなるため(Issue #823)。
/// 状態を確かめられない周期は gh を呼ぶ。Secret Service の無い機械では gh が鍵束を使わないため。
/// One cycle of the review thread, returning the lines for stderr. A cycle with a locked keyring
/// neither calls gh nor touches reviews.json: gh reading its token would request an unlock, and
/// without a display each request costs gnome-keyring-daemon one descriptor until it can no longer
/// open the keyring (Issue #823). A cycle with an unknown state still calls gh, since gh does not
/// use a keyring on a machine without a Secret Service.
///
/// last は最後に更新する。途中で panic した周期の行は、次の周期が書く。
/// last is updated at the end, so the line of a cycle that panicked is written by the next one.
fn review_cycle(
  keyring: &dyn Keyring,
  github: &dyn GitHub,
  ctx_dir: &Path,
  last: &mut KeyringState,
  now: DateTime<Utc>,
) -> Vec<String> {
  let current = keyring.state();
  let mut lines: Vec<String> = keyring_notice(*last, current)
    .map(str::to_string)
    .into_iter()
    .collect();
  if current != KeyringState::Locked {
    if let Err(reason) = refresh_reviews(github, ctx_dir, now) {
      lines.push(format!("レビュー依頼を更新できない: {reason}"));
    }
  }
  *last = current;
  lines
}

/// レビュー依頼のスレッドを立てる。本体は review_cycle を呼んで眠るだけの殻である。失敗は stderr に
/// 1 行書いて次の周期へ進み、万一の panic も周期の中で受け止める。スレッドが黙って死ぬと、reviews.json が
/// 古いまま誰も気づけないため。起動できなくても、agent の一覧と通知は続ける。
/// Starts the review thread, a thin shell that calls review_cycle and sleeps. Failures become
/// one stderr line and the next cycle follows; even an unexpected panic is caught per cycle, since
/// a silently dead thread would leave reviews.json stale with nobody noticing. If the thread cannot
/// start, the agent list and notices carry on.
fn spawn_reviews(
  keyring: impl Keyring + Send + 'static,
  github: impl GitHub + Send + 'static,
  ctx_dir: PathBuf,
  interval: Duration,
) {
  let spawned = thread::Builder::new()
    .name("reviews".to_string())
    .spawn(move || {
      let mut last = KeyringState::Unknown;
      loop {
        let cycle = panic::catch_unwind(AssertUnwindSafe(|| {
          review_cycle(&keyring, &github, &ctx_dir, &mut last, Utc::now())
        }));
        match cycle {
          Ok(lines) => lines.iter().for_each(|line| eprintln!("herdr-ctx: {line}")),
          Err(_) => eprintln!("herdr-ctx: レビュー依頼の周期が panic した。次の周期で続ける"),
        }
        thread::sleep(interval);
      }
    });
  if let Err(e) = spawned {
    eprintln!("herdr-ctx: レビュー依頼のスレッドを起動できない: {e}");
  }
}

pub fn run(
  herdr: &dyn Herdr,
  keyring: impl Keyring + Send + 'static,
  github: impl GitHub + Send + 'static,
  ctx_dir: &Path,
  options: &WatchOptions,
) -> ! {
  spawn_reviews(
    keyring,
    github,
    ctx_dir.to_path_buf(),
    options.reviews_interval,
  );
  let mut state = WatchState::load(ctx_dir);
  loop {
    tick(herdr, ctx_dir, &options.thresholds, &mut state, Utc::now());
    thread::sleep(options.interval);
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::testutil::{
    temp_dir, FakeGitHub, FakeHerdr, FakeKeyring, AGENT_LIST_JSON, NOTIFY_NOT_SHOWN_JSON,
    NOTIFY_SHOWN_JSON, SEARCH_EMPTY_JSON, SEARCH_JSON,
  };

  const THRESHOLDS: [u32; 3] = [50, 60, 80];

  fn row(pct: Option<u32>) -> Row {
    row_in("session-a", pct)
  }

  fn row_in(session_id: &str, pct: Option<u32>) -> Row {
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
      session_match: None,
      session_id: Some(session_id.to_string()),
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
  fn a_new_session_in_the_same_pane_starts_from_no_record() {
    let (state, _) = plan(
      &NotifyState::new(),
      &[row_in("session-a", Some(85))],
      &THRESHOLDS,
    );
    let (state, notices) = plan(&state, &[row_in("session-b", Some(62))], &THRESHOLDS);
    assert_eq!(notices.len(), 1);
    assert_eq!(notices[0].title, "worker-a context 62%");
    assert_eq!(
      state.get("w1:p1"),
      Some(&Notified {
        threshold: 60,
        session_id: Some("session-b".to_string()),
      })
    );
  }

  #[test]
  fn a_null_pct_does_not_carry_the_record_into_another_session() {
    let (state, _) = plan(
      &NotifyState::new(),
      &[row_in("session-a", Some(85))],
      &THRESHOLDS,
    );
    let (state, notices) = plan(&state, &[row_in("session-b", None)], &THRESHOLDS);
    assert!(state.is_empty());
    assert!(notices.is_empty());
  }

  #[test]
  fn a_mismatched_row_leaves_the_record_alone_and_stays_silent() {
    let (state, _) = plan(
      &NotifyState::new(),
      &[row_in("session-a", Some(62))],
      &THRESHOLDS,
    );
    let mut mismatched = row_in("session-b", Some(85));
    mismatched.session_match = Some(false);

    let (next, notices) = plan(&state, &[mismatched], &THRESHOLDS);

    assert_eq!(next, state);
    assert!(notices.is_empty());
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

  fn write_sidecar_file(ctx_dir: &Path, file: &str, pct: u32) {
    let panes = ctx_dir.join("panes");
    fs::create_dir_all(&panes).unwrap();
    let text = format!(r#"{{"used_percentage":{pct},"updated_at":"2026-11-05T12:34:56Z"}}"#);
    fs::write(panes.join(file), text).unwrap();
  }

  fn write_pane(ctx_dir: &Path, pct: u32) {
    write_sidecar_file(ctx_dir, "w3C_p1W.json", pct);
  }

  fn write_owned_pane(ctx_dir: &Path, session_id: &str, transcript_path: &str, pct: u32) {
    let panes = ctx_dir.join("panes");
    fs::create_dir_all(&panes).unwrap();
    let text = format!(
      r#"{{"session_id":"{session_id}","transcript_path":"{transcript_path}","used_percentage":{pct},"updated_at":"2026-11-05T12:34:56Z"}}"#
    );
    fs::write(panes.join("w3C_p1W.json"), text).unwrap();
  }

  fn level(state: &WatchState) -> Option<u32> {
    state.current.get("w3C:p1W").map(|record| record.threshold)
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
    let mut state = WatchState::default();

    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());
    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());

    let notified = herdr.notified.borrow();
    assert_eq!(notified.len(), 1);
    assert_eq!(notified[0].0, "commander-dotfiles context 62%");
    assert_eq!(notified[0].1, "dotfiles / working");

    let text = fs::read_to_string(dir.join(AGENTS_FILE)).unwrap();
    let file: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(file["generated_at"], "2026-11-05T12:35:00Z");
    assert_eq!(file["agents"].as_array().unwrap().len(), 3);
    assert_eq!(file["agents"][0]["pct"], 62);
  }

  #[test]
  fn a_sidecar_of_another_session_is_not_announced() {
    let dir = temp_dir("other-session");
    write_owned_pane(&dir, "session-old", "/t/session-old.jsonl", 62);
    let herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    let mut state = WatchState::default();

    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());

    assert!(herdr.notified.borrow().is_empty());
    assert!(state.current.is_empty());
    let text = fs::read_to_string(dir.join(AGENTS_FILE)).unwrap();
    let file: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(file["agents"][0]["session_match"], false);
    assert_eq!(file["agents"][0]["pct"], 62);
  }

  #[test]
  fn a_transcript_file_name_matching_the_agent_session_is_announced() {
    let dir = temp_dir("same-transcript");
    write_owned_pane(&dir, "session-job", "/t/session-a.jsonl", 62);
    let herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    let mut state = WatchState::default();

    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());

    assert_eq!(herdr.notified.borrow().len(), 1);
  }

  #[test]
  fn a_sidecar_without_a_session_id_is_announced() {
    let dir = temp_dir("no-session-id");
    write_pane(&dir, 62);
    let herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    let mut state = WatchState::default();

    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());

    assert_eq!(herdr.notified.borrow().len(), 1);
    let text = fs::read_to_string(dir.join(AGENTS_FILE)).unwrap();
    let file: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert!(file["agents"][0]["session_match"].is_null());
  }

  #[test]
  fn a_leftover_sidecar_under_another_kind_of_agent_is_not_announced() {
    let dir = temp_dir("leftover");
    write_sidecar_file(&dir, "w3U_p1.json", 70);
    let herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    let mut state = WatchState::default();

    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());

    assert!(herdr.notified.borrow().is_empty());
    assert!(state.current.is_empty());
  }

  #[test]
  fn the_state_survives_a_restart() {
    let dir = temp_dir("restart");
    write_pane(&dir, 62);
    let herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    let mut state = WatchState::default();
    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());

    let mut restarted = WatchState::load(&dir);
    assert_eq!(restarted.current, state.current);
    tick(&herdr, &dir, &THRESHOLDS, &mut restarted, now());
    assert_eq!(herdr.notified.borrow().len(), 1);
  }

  #[test]
  fn a_failed_save_is_retried_without_notifying_again() {
    let dir = temp_dir("save-retry");
    write_pane(&dir, 62);
    // 置き換え先がディレクトリだと rename が失敗する / rename fails onto a directory
    fs::create_dir(dir.join(STATE_FILE)).unwrap();
    let herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    let mut state = WatchState::default();

    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());
    assert_eq!(level(&state), Some(60));
    assert!(state.saved.is_empty());

    fs::remove_dir(dir.join(STATE_FILE)).unwrap();
    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());

    assert_eq!(state.saved, state.current);
    assert_eq!(load_state(&dir), state.current);
    assert_eq!(herdr.notified.borrow().len(), 1);
  }

  #[test]
  fn a_pending_save_is_retried_even_while_herdr_is_unreachable() {
    let dir = temp_dir("save-retry-down");
    write_pane(&dir, 62);
    fs::create_dir(dir.join(STATE_FILE)).unwrap();
    let mut herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    let mut state = WatchState::default();
    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());

    fs::remove_dir(dir.join(STATE_FILE)).unwrap();
    herdr.list = Err("no herdr server is running".to_string());
    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());

    assert_eq!(load_state(&dir), state.current);
  }

  #[test]
  fn a_failed_notice_is_retried_on_the_next_tick() {
    let dir = temp_dir("retry");
    write_pane(&dir, 62);
    let mut herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    herdr.notify_result = Err("no server".to_string());
    let mut state = WatchState::default();

    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());
    assert!(state.current.is_empty());

    herdr.notify_result = Ok(NOTIFY_SHOWN_JSON.to_string());
    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());
    assert_eq!(level(&state), Some(60));
  }

  #[test]
  fn a_notice_that_was_not_shown_is_retried_on_the_next_tick() {
    let dir = temp_dir("not-shown");
    write_pane(&dir, 62);
    let mut herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    herdr.notify_result = Ok(NOTIFY_NOT_SHOWN_JSON.to_string());
    let mut state = WatchState::default();

    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());
    assert!(state.current.is_empty());

    herdr.notify_result = Ok(NOTIFY_SHOWN_JSON.to_string());
    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());
    assert_eq!(level(&state), Some(60));
    assert_eq!(herdr.notified.borrow().len(), 2);
  }

  #[test]
  fn an_unreachable_herdr_keeps_the_state_and_writes_nothing() {
    let dir = temp_dir("unreachable");
    let mut herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    herdr.list = Err("no herdr server is running".to_string());
    let record = Notified {
      threshold: 60,
      session_id: None,
    };
    let current = NotifyState::from([("w3C:p1W".to_string(), record)]);
    let mut state = WatchState {
      saved: current.clone(),
      current,
    };

    tick(&herdr, &dir, &THRESHOLDS, &mut state, now());

    assert_eq!(level(&state), Some(60));
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

  fn read_reviews(dir: &Path) -> serde_json::Value {
    serde_json::from_str(&fs::read_to_string(dir.join(REVIEWS_FILE)).unwrap()).unwrap()
  }

  const PREVIOUS_REVIEWS: &str = "{\"previous\":true}\n";

  #[test]
  fn a_review_cycle_writes_reviews_json() {
    let dir = temp_dir("reviews");

    refresh_reviews(&FakeGitHub::answering(SEARCH_JSON), &dir, now()).unwrap();

    let file = read_reviews(&dir);
    assert_eq!(file["generated_at"], "2026-11-05T12:35:00Z");
    assert_eq!(file["total_count"], 152);
    assert_eq!(file["review_requests"].as_array().unwrap().len(), 3);
    assert_eq!(file["review_requests"][0]["repo"], "owner/zeta");
  }

  #[test]
  fn a_review_cycle_creates_the_ctx_dir() {
    let dir = temp_dir("reviews-mkdir").join("ctx");

    refresh_reviews(&FakeGitHub::answering(SEARCH_EMPTY_JSON), &dir, now()).unwrap();

    assert_eq!(read_reviews(&dir)["total_count"], 0);
  }

  #[test]
  fn no_requests_overwrite_the_previous_file_with_an_empty_list() {
    let dir = temp_dir("reviews-empty");
    fs::write(dir.join(REVIEWS_FILE), PREVIOUS_REVIEWS).unwrap();

    refresh_reviews(&FakeGitHub::answering(SEARCH_EMPTY_JSON), &dir, now()).unwrap();

    let file = read_reviews(&dir);
    assert_eq!(file["total_count"], 0);
    assert!(file["review_requests"].as_array().unwrap().is_empty());
  }

  #[test]
  fn a_failed_fetch_keeps_the_previous_file() {
    let dir = temp_dir("reviews-fail");
    fs::write(dir.join(REVIEWS_FILE), PREVIOUS_REVIEWS).unwrap();

    let error = refresh_reviews(&FakeGitHub::failing("gh: boom"), &dir, now()).unwrap_err();

    assert_eq!(error, "gh: boom");
    assert_eq!(
      fs::read_to_string(dir.join(REVIEWS_FILE)).unwrap(),
      PREVIOUS_REVIEWS
    );
  }

  #[test]
  fn a_broken_response_keeps_the_previous_file() {
    let dir = temp_dir("reviews-broken");
    fs::write(dir.join(REVIEWS_FILE), PREVIOUS_REVIEWS).unwrap();

    let error = refresh_reviews(&FakeGitHub::answering("not json"), &dir, now()).unwrap_err();

    assert!(error.starts_with("GitHub の JSON を読めない"), "{error}");
    assert_eq!(
      fs::read_to_string(dir.join(REVIEWS_FILE)).unwrap(),
      PREVIOUS_REVIEWS
    );
  }

  #[test]
  fn a_failed_write_is_reported() {
    let dir = temp_dir("reviews-write");
    // 置き換え先がディレクトリだと rename が失敗する / rename fails onto a directory
    fs::create_dir(dir.join(REVIEWS_FILE)).unwrap();

    let error = refresh_reviews(&FakeGitHub::answering(SEARCH_JSON), &dir, now()).unwrap_err();

    assert!(error.starts_with("reviews.json を書けない"), "{error}");
  }

  #[test]
  fn a_failed_fetch_writes_no_file() {
    let dir = temp_dir("reviews-none");

    assert!(refresh_reviews(&FakeGitHub::failing("gh: boom"), &dir, now()).is_err());

    assert!(!dir.join(REVIEWS_FILE).exists());
  }

  /// 鍵束の状態の列を 1 周期ずつ流して、周期ごとの行を返す。
  /// Feeds a sequence of keyring states, one per cycle, and returns the lines per cycle.
  fn cycle_lines(github: &FakeGitHub, dir: &Path, states: &[KeyringState]) -> Vec<Vec<String>> {
    let mut last = KeyringState::Unknown;
    states
      .iter()
      .map(|state| review_cycle(&FakeKeyring(*state), github, dir, &mut last, now()))
      .collect()
  }

  #[test]
  fn a_locked_keyring_skips_gh_and_keeps_the_previous_file() {
    let dir = temp_dir("keyring-locked");
    fs::write(dir.join(REVIEWS_FILE), PREVIOUS_REVIEWS).unwrap();
    let github = FakeGitHub::answering(SEARCH_JSON);

    cycle_lines(&github, &dir, &[KeyringState::Locked, KeyringState::Locked]);

    assert_eq!(github.calls.get(), 0);
    assert_eq!(
      fs::read_to_string(dir.join(REVIEWS_FILE)).unwrap(),
      PREVIOUS_REVIEWS
    );
  }

  #[test]
  fn a_locked_keyring_creates_no_file() {
    let dir = temp_dir("keyring-locked-none");

    cycle_lines(
      &FakeGitHub::answering(SEARCH_JSON),
      &dir,
      &[KeyringState::Locked],
    );

    assert!(!dir.join(REVIEWS_FILE).exists());
  }

  #[test]
  fn an_unlocked_or_unknown_keyring_still_calls_gh() {
    for state in [KeyringState::Unlocked, KeyringState::Unknown] {
      let dir = temp_dir(&format!("keyring-{state:?}"));
      fs::write(dir.join(REVIEWS_FILE), PREVIOUS_REVIEWS).unwrap();
      let github = FakeGitHub::answering(SEARCH_JSON);

      let lines = cycle_lines(&github, &dir, &[state]);

      assert_eq!(github.calls.get(), 1, "{state:?}");
      assert_eq!(read_reviews(&dir)["total_count"], 152, "{state:?}");
      assert!(lines[0].is_empty(), "{state:?}: {lines:?}");
    }
  }

  #[test]
  fn fetching_resumes_once_the_keyring_is_unlocked() {
    let dir = temp_dir("keyring-resume");
    let github = FakeGitHub::answering(SEARCH_JSON);

    cycle_lines(
      &github,
      &dir,
      &[KeyringState::Locked, KeyringState::Unlocked],
    );

    assert_eq!(github.calls.get(), 1);
    assert_eq!(read_reviews(&dir)["total_count"], 152);
  }

  #[test]
  fn lines_appear_only_when_skipping_starts_and_when_it_ends() {
    use KeyringState::{Locked, Unlocked};
    let dir = temp_dir("keyring-lines");

    let lines = cycle_lines(
      &FakeGitHub::answering(SEARCH_JSON),
      &dir,
      &[
        Locked, Locked, Locked, Unlocked, Unlocked, Locked, Locked, Unlocked,
      ],
    );

    let skipped = ["鍵束がロックされているので、レビュー依頼の取得を見送る".to_string()];
    let resumed = ["鍵束が解錠されたので、レビュー依頼の取得を再開する".to_string()];
    let none: [String; 0] = [];
    assert_eq!(lines[0], skipped);
    assert_eq!(lines[1], none);
    assert_eq!(lines[2], none);
    assert_eq!(lines[3], resumed);
    assert_eq!(lines[4], none);
    assert_eq!(lines[5], skipped);
    assert_eq!(lines[6], none);
    assert_eq!(lines[7], resumed);
  }

  #[test]
  fn losing_track_of_a_locked_keyring_says_once_that_fetching_resumes() {
    use KeyringState::{Locked, Unknown, Unlocked};
    let dir = temp_dir("keyring-lost");

    let lines = cycle_lines(
      &FakeGitHub::answering(SEARCH_JSON),
      &dir,
      &[Locked, Unknown, Unknown, Unlocked, Unknown],
    );

    assert_eq!(
      lines[1],
      ["鍵束の状態を確かめられないので、レビュー依頼の取得を再開する"]
    );
    assert!(lines[2..].iter().all(Vec::is_empty), "{lines:?}");
  }

  #[test]
  fn a_failed_fetch_is_still_reported_every_cycle() {
    let dir = temp_dir("keyring-fail");

    let lines = cycle_lines(
      &FakeGitHub::failing("gh: boom"),
      &dir,
      &[
        KeyringState::Locked,
        KeyringState::Unlocked,
        KeyringState::Unlocked,
      ],
    );

    let failed = "レビュー依頼を更新できない: gh: boom";
    assert_eq!(lines[0].len(), 1, "{lines:?}");
    assert_eq!(lines[1].len(), 2, "{lines:?}");
    assert_eq!(lines[1][1], failed);
    assert_eq!(lines[2], [failed]);
  }

  fn mode_of(path: &Path) -> u32 {
    fs::metadata(path).unwrap().permissions().mode() & 0o777
  }

  #[test]
  fn a_new_reviews_json_is_owner_only() {
    let dir = temp_dir("reviews-mode-new");

    refresh_reviews(&FakeGitHub::answering(SEARCH_JSON), &dir, now()).unwrap();

    assert_eq!(mode_of(&dir.join(REVIEWS_FILE)), 0o600);
  }

  #[test]
  fn a_world_readable_reviews_json_becomes_owner_only_once_replaced() {
    let dir = temp_dir("reviews-mode-replace");
    let path = dir.join(REVIEWS_FILE);
    fs::write(&path, PREVIOUS_REVIEWS).unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o644)).unwrap();

    refresh_reviews(&FakeGitHub::answering(SEARCH_JSON), &dir, now()).unwrap();

    assert_eq!(mode_of(&path), 0o600);
    assert_eq!(read_reviews(&dir)["total_count"], 152);
  }

  #[test]
  fn a_leftover_temp_file_with_another_mode_still_yields_owner_only() {
    let dir = temp_dir("reviews-mode-leftover");
    let path = dir.join(REVIEWS_FILE);
    let leftover = temp_path(&path);
    fs::write(&leftover, "{half").unwrap();
    fs::set_permissions(&leftover, fs::Permissions::from_mode(0o666)).unwrap();

    refresh_reviews(&FakeGitHub::answering(SEARCH_JSON), &dir, now()).unwrap();

    assert_eq!(mode_of(&path), 0o600);
    assert_eq!(read_reviews(&dir)["total_count"], 152);
    assert!(!leftover.exists());
  }
}
