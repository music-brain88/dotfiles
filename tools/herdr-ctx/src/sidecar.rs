//! statusline が書く sidecar の読み手。形は .config/claude/statusline-command.sh が決める。
//! Reader for the sidecar the statusline writes; statusline-command.sh defines its shape.

use serde::Deserialize;
use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};

/// sidecar のうち、herdr-ctx が使う鍵。ほかの鍵は読み飛ばす。
/// The sidecar keys herdr-ctx uses; the rest are ignored.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct Sidecar {
  pub used_percentage: Option<f64>,
  pub context_window_size: Option<u64>,
  pub total_input_tokens: Option<u64>,
  pub model_id: Option<String>,
  pub model_name: Option<String>,
  pub updated_at: Option<String>,
}

impl Sidecar {
  /// 使用率の整数値。statusline の 💭 と同じく切り捨てる。
  /// The integer percentage, truncated like the statusline's gauge.
  pub fn pct(&self) -> Option<u32> {
    self
      .used_percentage
      .map(|value| value.floor().max(0.0) as u32)
  }

  pub fn model(&self) -> Option<&str> {
    self.model_name.as_deref().or(self.model_id.as_deref())
  }
}

#[derive(Debug)]
pub enum SidecarRead {
  Found(Sidecar),
  Missing,
  Unreadable,
}

/// pane id の ':' はファイル名に向かないので '_' に置き換える。
/// ':' in a pane id is replaced with '_' for the file name.
pub fn sidecar_path(panes_dir: &Path, pane_id: &str) -> PathBuf {
  panes_dir.join(format!("{}.json", pane_id.replace(':', "_")))
}

pub fn read_sidecar(panes_dir: &Path, pane_id: &str) -> SidecarRead {
  match fs::read_to_string(sidecar_path(panes_dir, pane_id)) {
    Ok(text) => match serde_json::from_str(&text) {
      Ok(sidecar) => SidecarRead::Found(sidecar),
      Err(_) => SidecarRead::Unreadable,
    },
    Err(error) if error.kind() == ErrorKind::NotFound => SidecarRead::Missing,
    Err(_) => SidecarRead::Unreadable,
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::testutil::temp_dir;

  #[test]
  fn pane_id_maps_to_a_file_name() {
    let path = sidecar_path(Path::new("/x/panes"), "w3C:p1W");
    assert_eq!(path, PathBuf::from("/x/panes/w3C_p1W.json"));
  }

  #[test]
  fn pct_truncates_like_the_gauge() {
    let sidecar = |value| Sidecar {
      used_percentage: value,
      ..Sidecar::default()
    };
    assert_eq!(sidecar(Some(62.0)).pct(), Some(62));
    assert_eq!(sidecar(Some(62.9)).pct(), Some(62));
    assert_eq!(sidecar(None).pct(), None);
  }

  #[test]
  fn model_falls_back_to_the_id() {
    let sidecar = Sidecar {
      model_id: Some("claude-fable-5-1".to_string()),
      ..Sidecar::default()
    };
    assert_eq!(sidecar.model(), Some("claude-fable-5-1"));
  }

  #[test]
  fn read_tells_found_missing_and_unreadable_apart() {
    let dir = temp_dir("sidecar-read");
    assert!(matches!(read_sidecar(&dir, "w1:p1"), SidecarRead::Missing));

    fs::write(sidecar_path(&dir, "w1:p1"), "{broken").unwrap();
    assert!(matches!(
      read_sidecar(&dir, "w1:p1"),
      SidecarRead::Unreadable
    ));

    let text = r#"{"pane_id":"w1:p1","used_percentage":15,"context_window_size":1000000}"#;
    fs::write(sidecar_path(&dir, "w1:p1"), text).unwrap();
    match read_sidecar(&dir, "w1:p1") {
      SidecarRead::Found(sidecar) => {
        assert_eq!(sidecar.pct(), Some(15));
        assert_eq!(sidecar.context_window_size, Some(1_000_000));
      }
      other => panic!("{other:?}"),
    }
  }
}
