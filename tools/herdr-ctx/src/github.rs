//! GitHub との境界。`gh api` を子プロセスとして呼び、認証は gh に任せる。テストでは GitHub トレイトを
//! 固定の JSON で差し替える。
//! The boundary with GitHub. Calls `gh api` as a child process and leaves authentication to gh.
//! Tests swap the GitHub trait for fixed JSON.

use crate::process;
use chrono::{DateTime, SecondsFormat, Utc};
use serde::{Deserialize, Serialize};
use std::time::Duration;

/// 決定者個人に割り当てられた open のレビュー依頼を探す検索の条件。
/// The search for open review requests assigned to the decision maker personally.
pub const SEARCH_QUERY: &str = "is:pr is:open user-review-requested:@me";

/// 1 回の取得で受け取る件数の上限。検索 API の 1 ページの上限でもある。これを超える分はページを辿らず、
/// total_count で全体の数だけを示す。
/// The cap per fetch, which is also the search API's page limit. Beyond it no further pages are
/// read; total_count tells the full number.
pub const PER_PAGE: u32 = 100;

/// GitHub の呼び出し。結果は生の JSON で返し、解釈は fetch_reviews が受け持つ。
/// Calls into GitHub. Results stay raw JSON; fetch_reviews interprets them.
pub trait GitHub {
  fn search_review_requests(&self) -> Result<String, String>;
}

pub struct GhCli {
  timeout: Duration,
}

impl GhCli {
  pub fn new(timeout: Duration) -> Self {
    Self { timeout }
  }
}

impl GitHub for GhCli {
  /// 期限つきで呼ぶ。期限が無いと、gh が応答しないときに watch のレビュー依頼の周期が止まる。
  /// Called with a deadline; without one an unresponsive gh would stall watch's review cycle.
  fn search_review_requests(&self) -> Result<String, String> {
    let query = format!("q={SEARCH_QUERY}");
    let per_page = format!("per_page={PER_PAGE}");
    let args = [
      "api",
      "-X",
      "GET",
      "search/issues",
      "-f",
      &query,
      "-f",
      &per_page,
      "-f",
      "sort=updated",
      "-f",
      "order=desc",
    ];
    let finished = process::run("gh", &args, self.timeout)?;
    if finished.success {
      return Ok(finished.stdout);
    }
    Err(failure_reason(&finished.stdout, &finished.stderr))
  }
}

/// 検索 API の応答のうち、herdr-ctx が使う鍵。
/// The keys herdr-ctx uses from a search API response.
#[derive(Deserialize)]
struct SearchResponse {
  total_count: u64,
  #[serde(default)]
  incomplete_results: bool,
  items: Vec<SearchItem>,
}

#[derive(Deserialize)]
struct SearchItem {
  repository_url: String,
  number: u64,
  title: String,
  html_url: String,
  user: Option<User>,
  #[serde(default)]
  draft: bool,
  updated_at: String,
  created_at: String,
}

#[derive(Deserialize)]
struct User {
  login: String,
}

/// reviews.json の 1 件。鍵の順はこの宣言の順である。
/// One entry of reviews.json. Keys follow this declaration order.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct ReviewRequest {
  pub repo: String,
  pub number: u64,
  pub title: String,
  pub url: String,
  pub author: Option<String>,
  pub draft: bool,
  pub updated_at: String,
  pub created_at: String,
}

/// `herdr-ctx reviews` の出力と reviews.json の中身。読む側(盤面を映す窓)がこの形を読む。
/// The output of `herdr-ctx reviews` and the content of reviews.json, read by the board's window.
#[derive(Debug, Serialize)]
pub struct Reviews {
  pub generated_at: String,
  pub total_count: u64,
  pub review_requests: Vec<ReviewRequest>,
}

impl Reviews {
  pub fn to_json(&self) -> Result<String, String> {
    serde_json::to_string_pretty(self)
      .map(|text| text + "\n")
      .map_err(|e| format!("JSON を書けない: {e}"))
  }
}

/// `https://api.github.com/repos/owner/name` から `owner/name` を取り出す。GitHub Enterprise Server の
/// `https://<host>/api/v3/repos/owner/name` も同じ規則で読めるように、最初の `/repos/` より後ろを使う。
/// Takes `owner/name` out of `https://api.github.com/repos/owner/name`. The part after the first
/// `/repos/` is used, so a GitHub Enterprise Server URL reads the same way.
fn repo_of(repository_url: &str) -> Option<&str> {
  let (_, repo) = repository_url.split_once("/repos/")?;
  let (owner, name) = repo.split_once('/')?;
  let valid = !owner.is_empty() && !name.is_empty() && !name.contains('/');
  valid.then_some(repo)
}

/// 検索 API の応答を reviews.json の形にする。並び順は応答の順(sort=updated、order=desc)を保つ。
/// Turns a search API response into the reviews.json shape, keeping the response order
/// (sort=updated, order=desc).
pub fn parse_reviews(raw: &str, now: DateTime<Utc>) -> Result<Reviews, String> {
  let response: SearchResponse =
    serde_json::from_str(raw).map_err(|e| format!("GitHub の JSON を読めない: {e}"))?;
  // 打ち切られた結果で書き換えると、まだある依頼が一覧から消えて見える。前のファイルを残す方を選ぶ
  // Writing a truncated result would make live requests vanish, so the previous file wins
  if response.incomplete_results {
    return Err("GitHub の検索が途中で打ち切られた(incomplete_results)".to_string());
  }
  let review_requests = response
    .items
    .into_iter()
    .map(|item| {
      let repo = repo_of(&item.repository_url)
        .ok_or_else(|| format!("repository_url を読めない: {}", item.repository_url))?
        .to_string();
      Ok(ReviewRequest {
        repo,
        number: item.number,
        title: item.title,
        url: item.html_url,
        author: item.user.map(|user| user.login),
        draft: item.draft,
        updated_at: item.updated_at,
        created_at: item.created_at,
      })
    })
    .collect::<Result<Vec<_>, String>>()?;
  Ok(Reviews {
    generated_at: now.to_rfc3339_opts(SecondsFormat::Secs, true),
    total_count: response.total_count,
    review_requests,
  })
}

pub fn fetch_reviews(github: &dyn GitHub, now: DateTime<Utc>) -> Result<Reviews, String> {
  let raw = github.search_review_requests()?;
  parse_reviews(&raw, now)
}

/// GitHub の API が失敗したときに stdout に返す本文。
/// The body the GitHub API returns on stdout when a call fails.
#[derive(Deserialize)]
struct ApiError {
  message: Option<String>,
}

/// 失敗した gh の出力から、理由を 1 行にする。gh は stderr に `gh: Bad credentials (HTTP 401)` のような
/// 1 行を書き、stdout に API のエラーの本文を書く。
/// Reduces a failed gh run to a one-line reason. gh writes a line such as
/// `gh: Bad credentials (HTTP 401)` to stderr and the API's error body to stdout.
fn failure_reason(stdout: &str, stderr: &str) -> String {
  if let Some(line) = stderr.lines().map(str::trim).find(|line| !line.is_empty()) {
    return line.to_string();
  }
  serde_json::from_str::<ApiError>(stdout)
    .ok()
    .and_then(|error| error.message)
    .or_else(|| {
      stdout
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .map(str::to_string)
    })
    .unwrap_or_else(|| "gh が失敗した".to_string())
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::testutil::{FakeGitHub, SEARCH_EMPTY_JSON, SEARCH_JSON};

  fn now() -> DateTime<Utc> {
    DateTime::parse_from_rfc3339("2026-11-14T02:13:38Z")
      .unwrap()
      .with_timezone(&Utc)
  }

  #[test]
  fn the_response_becomes_the_reviews_shape() {
    let reviews = parse_reviews(SEARCH_JSON, now()).unwrap();
    assert_eq!(reviews.generated_at, "2026-11-14T02:13:38Z");
    assert_eq!(reviews.total_count, 152);
    assert_eq!(
      reviews.review_requests[0],
      ReviewRequest {
        repo: "owner/zeta".to_string(),
        number: 123,
        title: "Add the widget".to_string(),
        url: "https://github.com/owner/zeta/pull/123".to_string(),
        author: Some("author-a".to_string()),
        draft: false,
        updated_at: "2026-11-13T09:00:00Z".to_string(),
        created_at: "2026-11-10T01:00:00Z".to_string(),
      }
    );
  }

  #[test]
  fn the_response_order_is_kept() {
    let reviews = parse_reviews(SEARCH_JSON, now()).unwrap();
    let order: Vec<(&str, u64)> = reviews
      .review_requests
      .iter()
      .map(|request| (request.repo.as_str(), request.number))
      .collect();
    assert_eq!(
      order,
      [
        ("owner/zeta", 123),
        ("example-org/alpha", 7),
        ("owner/zeta", 98)
      ]
    );
  }

  #[test]
  fn a_missing_user_or_draft_is_tolerated() {
    let reviews = parse_reviews(SEARCH_JSON, now()).unwrap();
    let last = &reviews.review_requests[2];
    assert_eq!(last.author, None);
    assert!(!last.draft);
    assert!(reviews.review_requests[1].draft);
  }

  #[test]
  fn no_requests_is_an_empty_list() {
    let reviews = parse_reviews(SEARCH_EMPTY_JSON, now()).unwrap();
    assert_eq!(reviews.total_count, 0);
    assert!(reviews.review_requests.is_empty());
  }

  #[test]
  fn the_repo_comes_from_the_repository_url() {
    assert_eq!(
      repo_of("https://api.github.com/repos/owner/name"),
      Some("owner/name")
    );
    assert_eq!(
      repo_of("https://ghe.example/api/v3/repos/owner/name"),
      Some("owner/name")
    );
    assert_eq!(
      repo_of("https://api.github.com/repos/repos/name"),
      Some("repos/name")
    );
    assert_eq!(repo_of("https://api.github.com/repos/owner"), None);
    assert_eq!(repo_of("https://api.github.com/repos/owner/"), None);
    assert_eq!(repo_of("https://api.github.com/repos/a/b/c"), None);
    assert_eq!(repo_of("https://api.github.com/users/owner"), None);
  }

  #[test]
  fn an_unreadable_repository_url_is_an_error() {
    let raw = SEARCH_EMPTY_JSON.replace(
      r#""items":[]"#,
      r#""items":[{"repository_url":"https://example.com/x","number":1,"title":"t","html_url":"u","updated_at":"a","created_at":"b"}]"#,
    );
    let error = parse_reviews(&raw, now()).unwrap_err();
    assert_eq!(error, "repository_url を読めない: https://example.com/x");
  }

  #[test]
  fn incomplete_results_are_an_error() {
    let raw = SEARCH_JSON.replace(
      r#""incomplete_results":false"#,
      r#""incomplete_results":true"#,
    );
    let error = parse_reviews(&raw, now()).unwrap_err();
    assert!(error.contains("incomplete_results"), "{error}");
  }

  #[test]
  fn broken_json_is_an_error() {
    let error = parse_reviews("not json", now()).unwrap_err();
    assert!(error.starts_with("GitHub の JSON を読めない"), "{error}");
    let error = parse_reviews(r#"{"total_count":1}"#, now()).unwrap_err();
    assert!(error.starts_with("GitHub の JSON を読めない"), "{error}");
  }

  #[test]
  fn fetch_passes_a_failure_through() {
    let github = FakeGitHub::failing("gh: Bad credentials (HTTP 401)");
    let error = fetch_reviews(&github, now()).unwrap_err();
    assert_eq!(error, "gh: Bad credentials (HTTP 401)");
  }

  #[test]
  fn the_json_keeps_the_key_order_of_the_issue() {
    let reviews = parse_reviews(SEARCH_JSON, now()).unwrap();
    let text = reviews.to_json().unwrap();
    assert!(text.starts_with("{\n  \"generated_at\": "), "{text}");
    assert!(text.ends_with("}\n"), "{text}");
    let item = serde_json::to_string(&reviews.review_requests[0]).unwrap();
    assert_eq!(
      item,
      r#"{"repo":"owner/zeta","number":123,"title":"Add the widget","url":"https://github.com/owner/zeta/pull/123","author":"author-a","draft":false,"updated_at":"2026-11-13T09:00:00Z","created_at":"2026-11-10T01:00:00Z"}"#
    );
  }

  #[test]
  fn failure_reason_prefers_the_stderr_line() {
    let body =
      r#"{"message":"Bad credentials","documentation_url":"https://docs.github.com/rest"}"#;
    assert_eq!(
      failure_reason(body, "\ngh: Bad credentials (HTTP 401)\n"),
      "gh: Bad credentials (HTTP 401)"
    );
  }

  #[test]
  fn failure_reason_falls_back_to_the_api_message_then_to_a_fixed_text() {
    let body = r#"{"message":"Bad credentials"}"#;
    assert_eq!(failure_reason(body, ""), "Bad credentials");
    assert_eq!(failure_reason("boom\n", ""), "boom");
    assert_eq!(failure_reason("", ""), "gh が失敗した");
  }
}
