//! 子プロセスを期限つきで実行する。herdr と gh の呼び出しが共有する。
//! Runs a child process with a deadline. Shared by the herdr and gh calls.

use std::io::Read;
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::thread;
use std::time::{Duration, Instant};

/// 子プロセスの終了を確かめる間隔。
/// How often the child's exit is checked.
const POLL_INTERVAL: Duration = Duration::from_millis(50);

/// 子プロセスが終わった後に、出力を読み切るまで待つ上限。
/// How long to wait for the remaining output once the child has exited.
const DRAIN_TIMEOUT: Duration = Duration::from_millis(200);

/// 期限内に終わった子プロセスの結果。終了コードの解釈は呼び出し側が受け持つ。
/// The result of a child that finished in time. Callers interpret the exit status.
pub struct Finished {
  pub success: bool,
  pub stdout: String,
  pub stderr: String,
}

/// program を期限つきで実行する。相手が要求を受けたまま応答しないと、watch の周期が止まり、
/// self は hook の timeout に切られて使用率の行を出せなくなる。
/// Runs program with a deadline. If it accepts a request and never answers, watch would stall
/// and self would be cut off by the hook timeout before printing the usage line.
pub fn run(program: &str, args: &[&str], timeout: Duration) -> Result<Finished, String> {
  let mut child = Command::new(program)
    .args(args)
    .stdin(Stdio::null())
    .stdout(Stdio::piped())
    .stderr(Stdio::piped())
    .spawn()
    .map_err(|e| format!("{program} を実行できない: {e}"))?;
  let stdout = read_in_background(child.stdout.take());
  let stderr = read_in_background(child.stderr.take());
  let status = wait_with_deadline(program, &mut child, timeout)?;
  Ok(Finished {
    success: status.success(),
    stdout: drain(&stdout),
    stderr: drain(&stderr),
  })
}

/// 待つ間も別のスレッドで読み続ける。パイプが満杯になると子プロセスが書けずに止まるため。
/// Keeps reading on another thread while waiting, since a full pipe would block the child.
fn read_in_background<R: Read + Send + 'static>(pipe: Option<R>) -> Receiver<Vec<u8>> {
  let (sender, receiver) = mpsc::channel();
  thread::spawn(move || {
    let mut bytes = Vec::new();
    if let Some(mut pipe) = pipe {
      let _ = pipe.read_to_end(&mut bytes);
    }
    let _ = sender.send(bytes);
  });
  receiver
}

fn drain(receiver: &Receiver<Vec<u8>>) -> String {
  let bytes = receiver.recv_timeout(DRAIN_TIMEOUT).unwrap_or_default();
  String::from_utf8_lossy(&bytes).into_owned()
}

/// 期限を過ぎたら子プロセスを止めて回収する。読み手のスレッドは待たない。子プロセスの子孫がパイプを
/// 握っていると、読み手はその子孫が終わるまで終わらないので、待つと期限の意味が無くなる。
/// Past the deadline the child is killed and reaped without waiting for the reader threads: a
/// descendant holding the pipe would keep them alive and defeat the deadline.
fn wait_with_deadline(
  program: &str,
  child: &mut Child,
  timeout: Duration,
) -> Result<ExitStatus, String> {
  let deadline = Instant::now() + timeout;
  loop {
    match child.try_wait() {
      Ok(Some(status)) => return Ok(status),
      Ok(None) if Instant::now() >= deadline => {
        let _ = child.kill();
        let _ = child.wait();
        return Err(format!(
          "{program} が {} 秒以内に応答しない",
          timeout.as_secs()
        ));
      }
      Ok(None) => thread::sleep(POLL_INTERVAL),
      Err(e) => return Err(format!("{program} の終了を待てない: {e}")),
    }
  }
}
