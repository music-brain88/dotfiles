//! claudia-memory の標準入出力の口。1 行に 1 つの JSON-RPC メッセージを読み、返事を 1 行で書く。
//! The stdio transport of claudia-memory: one JSON-RPC message per line in, one reply per line out.

use std::env;
use std::io::{self, BufRead, Write};
use std::path::PathBuf;
use std::process::ExitCode;

use claudia_memory::mcp;
use claudia_memory::store::FsStore;

const USAGE: &str = "claudia-memory — AgentMemory を MCP (stdio) で読ませる関所

使い方 / Usage:
  claudia-memory [--root <AgentMemory のフォルダ>]

  --root   AgentMemory のルート。省くと、環境変数 CLAUDIA_MEMORY_ROOT、
           それも無ければ ~/Documents/Obsidian/AgentMemory を使う。
           The AgentMemory root. Defaults to $CLAUDIA_MEMORY_ROOT, then ~/Documents/Obsidian/AgentMemory.
  --version, --help";

fn default_root() -> Option<PathBuf> {
  if let Some(root) = env::var_os("CLAUDIA_MEMORY_ROOT") {
    if !root.is_empty() {
      return Some(PathBuf::from(root));
    }
  }
  env::var_os("HOME").map(|home| PathBuf::from(home).join("Documents/Obsidian/AgentMemory"))
}

fn main() -> ExitCode {
  let mut root: Option<PathBuf> = None;
  let mut args = env::args().skip(1);
  while let Some(arg) = args.next() {
    match arg.as_str() {
      "--help" | "-h" => {
        println!("{USAGE}");
        return ExitCode::SUCCESS;
      }
      "--version" | "-V" => {
        println!("claudia-memory {}", env!("CARGO_PKG_VERSION"));
        return ExitCode::SUCCESS;
      }
      "--root" => match args.next() {
        Some(value) => root = Some(PathBuf::from(value)),
        None => {
          eprintln!("claudia-memory: --root には値が要る\n\n{USAGE}");
          return ExitCode::from(2);
        }
      },
      other => {
        eprintln!("claudia-memory: 知らない引数: {other}\n\n{USAGE}");
        return ExitCode::from(2);
      }
    }
  }

  let Some(root) = root.or_else(default_root) else {
    eprintln!(
      "claudia-memory: AgentMemory のルートが決まらない (--root か CLAUDIA_MEMORY_ROOT を指定する)"
    );
    return ExitCode::from(2);
  };
  let store = match FsStore::open(&root) {
    Ok(store) => store,
    Err(e) => {
      eprintln!("claudia-memory: AgentMemory のルートを開けない。{e}");
      return ExitCode::from(1);
    }
  };

  let stdin = io::stdin();
  let mut stdout = io::stdout().lock();
  for line in stdin.lock().lines() {
    let Ok(line) = line else { break };
    let line = line.trim();
    if line.is_empty() {
      continue;
    }
    let reply = match serde_json::from_str(line) {
      Ok(message) => mcp::handle(&store, &message),
      Err(_) => Some(mcp::parse_error()),
    };
    if let Some(reply) = reply {
      // 標準出力が閉じられたら、クライアントが去ったということなので終える。
      // A closed stdout means the client is gone; stop.
      if writeln!(stdout, "{reply}").is_err() || stdout.flush().is_err() {
        break;
      }
    }
  }
  ExitCode::SUCCESS
}
