//! ログイン鍵束(Secret Service の既定のコレクション)との境界。`busctl` を子プロセスとして呼び、ロックされて
//! いるかだけを読む。テストでは Keyring トレイトを固定の状態で差し替える。
//! The boundary with the login keyring (the Secret Service's default collection). Calls `busctl` as
//! a child process and only reads whether it is locked. Tests swap the Keyring trait for a fixed
//! state.

use crate::process::{self, Finished};
use std::time::Duration;

/// 既定のコレクションの Locked プロパティを読む引数。プロパティの読み取りは解錠を要求しないので、
/// 解錠のダイアログ(gcr-prompter)を起動しない。daemon の自動起動は止めない。起動の直後で daemon がまだ
/// いないときに「確かめられない」になると、続く gh が daemon を起こして解錠を要求してしまうため。
/// Reads the default collection's Locked property. Reading a property requests no unlock, so it
/// never starts the unlock dialog (gcr-prompter). Auto-start stays on: with no daemon running yet
/// right after boot the state would be unknown, and the gh call that follows would start the daemon
/// and request an unlock.
const LOCKED_ARGS: [&str; 6] = [
  "--user",
  "get-property",
  "org.freedesktop.secrets",
  "/org/freedesktop/secrets/aliases/default",
  "org.freedesktop.Secret.Collection",
  "Locked",
];

/// 鍵束の状態。Unknown は、Secret Service が無い、busctl が無い、期限切れ、出力を解釈できないのどれかを表す。
/// The keyring's state. Unknown covers no Secret Service, no busctl, a timeout and unreadable output.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum KeyringState {
  Locked,
  Unlocked,
  Unknown,
}

pub trait Keyring {
  fn state(&self) -> KeyringState;
}

pub struct BusctlKeyring {
  timeout: Duration,
}

impl BusctlKeyring {
  pub fn new(timeout: Duration) -> Self {
    Self { timeout }
  }
}

impl Keyring for BusctlKeyring {
  fn state(&self) -> KeyringState {
    interpret(process::run("busctl", &LOCKED_ARGS, self.timeout))
  }
}

/// busctl の結果を状態に読み替える。はっきり読めたときだけ Locked か Unlocked とし、他はすべて Unknown とする。
/// Turns a busctl result into a state. Only a clear answer is Locked or Unlocked; anything else is
/// Unknown.
fn interpret(result: Result<Finished, String>) -> KeyringState {
  match result {
    Ok(finished) if finished.success => match finished.stdout.trim() {
      "b true" => KeyringState::Locked,
      "b false" => KeyringState::Unlocked,
      _ => KeyringState::Unknown,
    },
    _ => KeyringState::Unknown,
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn finished(success: bool, stdout: &str) -> Result<Finished, String> {
    Ok(Finished {
      success,
      stdout: stdout.to_string(),
      stderr: String::new(),
    })
  }

  #[test]
  fn b_true_is_locked() {
    assert_eq!(interpret(finished(true, "b true\n")), KeyringState::Locked);
  }

  #[test]
  fn b_false_is_unlocked() {
    assert_eq!(
      interpret(finished(true, "b false\n")),
      KeyringState::Unlocked
    );
  }

  #[test]
  fn unexpected_output_is_unknown() {
    for stdout in [
      "",
      "\n",
      "true",
      "b",
      "b TRUE",
      "s \"true\"",
      "b true\nb false\n",
    ] {
      assert_eq!(
        interpret(finished(true, stdout)),
        KeyringState::Unknown,
        "{stdout:?}"
      );
    }
  }

  #[test]
  fn a_failed_busctl_is_unknown_whatever_it_printed() {
    for stdout in ["", "b true\n", "b false\n"] {
      assert_eq!(
        interpret(finished(false, stdout)),
        KeyringState::Unknown,
        "{stdout:?}"
      );
    }
  }

  #[test]
  fn a_busctl_that_cannot_run_or_times_out_is_unknown() {
    let reason = "busctl を実行できない: No such file or directory (os error 2)";
    assert_eq!(interpret(Err(reason.to_string())), KeyringState::Unknown);
    let reason = "busctl が 10 秒以内に応答しない";
    assert_eq!(interpret(Err(reason.to_string())), KeyringState::Unknown);
  }
}
