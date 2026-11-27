# claudia-memory: AgentMemory を MCP (stdio) で読ませる関所(Rust)。
# flake.nix の overlay から callPackage され、nix/modules/dev-tools.nix の home.packages で配る。
# Built via overlay in flake.nix and shipped through home.packages (dev-tools.nix).
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "claudia-memory";
  version = "0.1.0";

  src = lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;

  # tests/cli.rs は一時フォルダに小さな AgentMemory を作ってバイナリを起動するだけなので、
  # ビルドサンドボックス内でも cargo test が通る。本物の vault は読まない
  # tests/cli.rs builds a small AgentMemory tree in a temp folder and spawns the binary, so
  # `cargo test` runs inside the build sandbox without touching the real vault.
  doCheck = true;

  meta = with lib; {
    description = "AgentMemory を MCP (stdio) で読ませる関所";
    homepage = "https://github.com/music-brain88/dotfiles/tree/main/tools/claudia-memory";
    license = licenses.mit;
    mainProgram = "claudia-memory";
    platforms = platforms.linux;
  };
}
