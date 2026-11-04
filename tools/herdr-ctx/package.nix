# herdr-ctx: herdr の各 agent の context 使用率を読む CLI(Rust)。
# flake.nix の overlay から callPackage され、nix/modules/herdr.nix の home.packages で配る。
# Built via overlay in flake.nix and shipped through home.packages (herdr.nix).
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "herdr-ctx";
  version = "0.1.0";

  src = lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;

  # tests/cli.rs の偽 herdr は組み込みコマンドだけを使う /bin/sh スクリプトなので、
  # ビルドサンドボックス内でも cargo test が通る
  # The fake herdr in tests/cli.rs is a /bin/sh script using builtins only, so `cargo test`
  # runs inside the build sandbox.
  doCheck = true;

  meta = with lib; {
    description = "herdr の各 agent の context 使用率を pane の幅に依存せず読む CLI";
    homepage = "https://github.com/music-brain88/dotfiles/tree/main/tools/herdr-ctx";
    license = licenses.mit;
    mainProgram = "herdr-ctx";
    platforms = platforms.linux;
  };
}
