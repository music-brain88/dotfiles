//! MCP の口。JSON-RPC の 1 メッセージを受けて、返すメッセージ (あれば) を作る。運び方は知らない。
//! The MCP surface: takes one JSON-RPC message and produces the reply, if any. Knows nothing of the transport.

use serde_json::{json, Value};

use crate::recall;
use crate::store::{RelPath, Store};

pub const TOOL_RECALL: &str = "claudia_memory_recall";
const DEFAULT_PROTOCOL: &str = "2025-06-18";

/// サーバーの説明文。届かないクライアントもある (2026-11 の Claude デスクトップ版の Chat には届かなかった) ので、
/// 起動の合図はこれに頼らず、クライアント側の指示文に置く。届くクライアントのために書いておく。
/// Server instructions. Some clients never surface them (Claude desktop Chat did not, as of 2026-11), so the
/// start-of-conversation cue lives in the client's own instructions; this text serves the clients that do.
const INSTRUCTIONS: &str = "クラウディアの記憶 (AgentMemory) を読むサーバーである。会話の最初に claudia_memory_recall を引数なしで呼び、返ってきた索引に従って記憶を読むこと。";

fn tool_definition() -> Value {
  json!({
    "name": TOOL_RECALL,
    "description": "クラウディアの記憶 (AgentMemory) を読む。会話の最初に、引数なしで 1 回呼ぶこと。引数なしで呼ぶと、人格の索引 (core/MEMORY.md) と「家」の索引 (home/MEMORY.md) が返る。返ってきた「ここから辿れる記憶」のパスを path に渡すと、その記憶を読める。各ファイルに付く version は、あとでその記憶を直すときに使う版の印である。",
    "inputSchema": {
      "type": "object",
      "properties": {
        "path": {
          "type": "string",
          "description": "読みたい記憶のパス。AgentMemory のルートからの相対パスで、.md で終わる (例: core/self-model.md)。省くと、最初に読む 2 つの索引が返る。"
        }
      },
      "additionalProperties": false
    }
  })
}

fn ok(id: &Value, result: Value) -> Value {
  json!({ "jsonrpc": "2.0", "id": id, "result": result })
}

fn error(id: &Value, code: i64, message: &str) -> Value {
  json!({ "jsonrpc": "2.0", "id": id, "error": { "code": code, "message": message } })
}

/// ツールの結果。失敗はプロトコルのエラーにせず、isError を立てたテキストで返す (モデルが読んで直せるように)。
/// A tool result. Failures are reported as text with isError set, not as protocol errors, so the model can react.
fn tool_text(id: &Value, text: String, is_error: bool) -> Value {
  ok(
    id,
    json!({ "content": [{ "type": "text", "text": text }], "isError": is_error }),
  )
}

fn call_recall(store: &dyn Store, id: &Value, arguments: &Value) -> Value {
  let path = match arguments.get("path") {
    None | Some(Value::Null) => None,
    Some(Value::String(s)) if s.trim().is_empty() => None,
    Some(Value::String(s)) => Some(s.as_str()),
    Some(_) => return tool_text(id, "path は文字列で渡すこと。".into(), true),
  };
  let recalled = match path {
    None => recall::recall_start(store),
    Some(raw) => RelPath::parse(raw)
      .and_then(|p| recall::recall(store, &p))
      .map(|r| vec![r]),
  };
  match recalled {
    Ok(items) => tool_text(id, recall::render(&items), false),
    Err(e) => tool_text(id, format!("記憶を読めなかった。{e}"), true),
  }
}

/// 1 メッセージを処理する。通知 (id の無いメッセージ) には何も返さない。
/// Handles one message. Notifications (messages without an id) get no reply.
pub fn handle(store: &dyn Store, message: &Value) -> Option<Value> {
  let method = message.get("method").and_then(Value::as_str).unwrap_or("");
  let id = message.get("id")?;
  let params = message.get("params").cloned().unwrap_or(Value::Null);
  let reply = match method {
    "initialize" => {
      let protocol = params
        .get("protocolVersion")
        .and_then(Value::as_str)
        .unwrap_or(DEFAULT_PROTOCOL);
      ok(
        id,
        json!({
          "protocolVersion": protocol,
          "capabilities": { "tools": {} },
          "serverInfo": { "name": "claudia-memory", "version": env!("CARGO_PKG_VERSION") },
          "instructions": INSTRUCTIONS
        }),
      )
    }
    "ping" => ok(id, json!({})),
    "tools/list" => ok(id, json!({ "tools": [tool_definition()] })),
    "tools/call" => {
      let name = params.get("name").and_then(Value::as_str).unwrap_or("");
      let arguments = params.get("arguments").cloned().unwrap_or(Value::Null);
      if name == TOOL_RECALL {
        call_recall(store, id, &arguments)
      } else {
        error(id, -32602, &format!("unknown tool: {name}"))
      }
    }
    other => error(id, -32601, &format!("method not found: {other}")),
  };
  Some(reply)
}

/// JSON として読めなかった行への返事。 / The reply to a line that is not valid JSON.
pub fn parse_error() -> Value {
  error(&Value::Null, -32700, "parse error")
}
