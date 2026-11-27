//! claudia-memory: AgentMemory を MCP で読ませる関所。
//! 規則を持つ部分 (store・recall) を、運び方 (mcp と main の標準入出力) から切り離してある。
//! あとで HTTP の口や別の保存先を足すときは、store と recall をそのまま使う。
//!
//! claudia-memory: an MCP gatekeeper for the AgentMemory vault.
//! The rule-bearing parts (store, recall) are kept apart from the transport (mcp, and stdio in main),
//! so an HTTP transport or another storage backend can reuse them as they are.

pub mod mcp;
pub mod recall;
pub mod store;
