//! herdr CLI との境界。テストでは Herdr トレイトを固定の JSON で差し替える。
//! The boundary with the herdr CLI. Tests swap the Herdr trait for fixed JSON.

use serde::de::DeserializeOwned;
use serde::Deserialize;
use std::process::Command;

/// herdr の呼び出し。結果は生の JSON で返し、解釈は list_agents と get_agent が受け持つ。
/// Calls into herdr. Results stay raw JSON; list_agents and get_agent interpret them.
pub trait Herdr {
  fn agent_list(&self) -> Result<String, String>;
  fn agent_get(&self, target: &str) -> Result<String, String>;
  fn notify(&self, title: &str, body: &str) -> Result<(), String>;
}

pub struct HerdrCli;

impl HerdrCli {
  fn run(args: &[&str]) -> Result<String, String> {
    let output = Command::new("herdr")
      .args(args)
      .output()
      .map_err(|e| format!("herdr を実行できない: {e}"))?;
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    if output.status.success() {
      return Ok(stdout);
    }
    let stderr = String::from_utf8_lossy(&output.stderr);
    Err(failure_reason(&stdout, &stderr))
  }
}

impl Herdr for HerdrCli {
  fn agent_list(&self) -> Result<String, String> {
    Self::run(&["agent", "list"])
  }

  fn agent_get(&self, target: &str) -> Result<String, String> {
    Self::run(&["agent", "get", target])
  }

  fn notify(&self, title: &str, body: &str) -> Result<(), String> {
    Self::run(&[
      "notification",
      "show",
      title,
      "--body",
      body,
      "--sound",
      "request",
    ])
    .map(|_| ())
  }
}

/// `herdr agent list` と `herdr agent get` の要素のうち、herdr-ctx が使う鍵。
/// The keys herdr-ctx uses from an element of `herdr agent list` / `herdr agent get`.
#[derive(Debug, Clone, Deserialize)]
pub struct Agent {
  pub pane_id: String,
  pub name: Option<String>,
  pub agent_status: Option<String>,
  pub cwd: Option<String>,
}

/// herdr の応答の封筒。成功は result、失敗は error に入る。
/// herdr's response envelope: success in result, failure in error.
#[derive(Deserialize)]
struct Envelope<T> {
  result: Option<T>,
  error: Option<ApiError>,
}

#[derive(Deserialize)]
struct ApiError {
  code: Option<String>,
  message: Option<String>,
}

impl ApiError {
  fn describe(&self) -> String {
    self
      .message
      .clone()
      .or_else(|| self.code.clone())
      .unwrap_or_else(|| "herdr がエラーを返した".to_string())
  }
}

#[derive(Deserialize)]
struct AgentList {
  agents: Vec<Agent>,
}

#[derive(Deserialize)]
struct AgentInfo {
  agent: Agent,
}

fn parse_result<T: DeserializeOwned>(raw: &str) -> Result<T, String> {
  let envelope: Envelope<T> =
    serde_json::from_str(raw).map_err(|e| format!("herdr の JSON を読めない: {e}"))?;
  match (envelope.result, envelope.error) {
    (Some(result), _) => Ok(result),
    (None, Some(error)) => Err(error.describe()),
    (None, None) => Err("herdr の応答に result が無い".to_string()),
  }
}

pub fn list_agents(herdr: &dyn Herdr) -> Result<Vec<Agent>, String> {
  let raw = herdr.agent_list()?;
  parse_result::<AgentList>(&raw).map(|list| list.agents)
}

pub fn get_agent(herdr: &dyn Herdr, target: &str) -> Result<Agent, String> {
  let raw = herdr.agent_get(target)?;
  parse_result::<AgentInfo>(&raw).map(|info| info.agent)
}

/// 失敗した herdr の出力から、理由を 1 行にする。herdr はエラーも JSON で返す。
/// Reduces a failed herdr run to a one-line reason. herdr reports errors as JSON too.
fn failure_reason(stdout: &str, stderr: &str) -> String {
  for text in [stdout, stderr] {
    if let Ok(envelope) = serde_json::from_str::<Envelope<serde_json::Value>>(text) {
      if let Some(error) = envelope.error {
        return error.describe();
      }
    }
  }
  stderr
    .lines()
    .chain(stdout.lines())
    .map(str::trim)
    .find(|line| !line.is_empty())
    .unwrap_or("herdr が失敗した")
    .to_string()
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::testutil::{FakeHerdr, AGENT_GET_JSON, AGENT_LIST_JSON};

  #[test]
  fn list_reads_the_envelope_and_allows_a_missing_name() {
    let agents = list_agents(&FakeHerdr::with_list(AGENT_LIST_JSON)).unwrap();
    assert_eq!(agents.len(), 2);
    assert_eq!(agents[0].name.as_deref(), Some("commander-dotfiles"));
    assert_eq!(agents[0].pane_id, "w3C:p1W");
    assert_eq!(agents[0].agent_status.as_deref(), Some("working"));
    assert_eq!(agents[1].name, None);
  }

  #[test]
  fn get_reads_the_agent_inside_the_envelope() {
    let mut herdr = FakeHerdr::with_list(AGENT_LIST_JSON);
    herdr.get = Ok(AGENT_GET_JSON.to_string());
    let agent = get_agent(&herdr, "w3C:p1W").unwrap();
    assert_eq!(agent.name.as_deref(), Some("commander-dotfiles"));
  }

  #[test]
  fn error_envelope_becomes_its_message() {
    let raw = r#"{"id":"cli:agent:list","error":{"code":"server_not_running","message":"no herdr server is running"}}"#;
    let error = list_agents(&FakeHerdr::with_list(raw)).unwrap_err();
    assert_eq!(error, "no herdr server is running");
  }

  #[test]
  fn broken_json_is_an_error() {
    let error = list_agents(&FakeHerdr::with_list("not json")).unwrap_err();
    assert!(error.starts_with("herdr の JSON を読めない"), "{error}");
  }

  #[test]
  fn failure_reason_prefers_the_json_error_on_either_stream() {
    let json = r#"{"error":{"code":"agent_not_found","message":"agent target x not found"}}"#;
    assert_eq!(failure_reason(json, ""), "agent target x not found");
    assert_eq!(failure_reason("", json), "agent target x not found");
  }

  #[test]
  fn failure_reason_falls_back_to_the_first_line() {
    assert_eq!(failure_reason("", "\nboom\nmore\n"), "boom");
    assert_eq!(failure_reason("", ""), "herdr が失敗した");
  }
}
