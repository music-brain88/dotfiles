# herdr-ctx: 盤面の値(各 agent の context 使用率と、決定者宛ての open のレビュー依頼)を集める CLI(Rust)。
# flake.nix の overlay から callPackage され、nix/modules/herdr.nix の home.packages で配る。
# Built via overlay in flake.nix and shipped through home.packages (herdr.nix).
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "herdr-ctx";
  version = "0.1.0";

  src = lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;

  # tests/cli.rs の偽 herdr と偽 gh は組み込みコマンドだけを使う /bin/sh スクリプトなので、
  # ビルドサンドボックス内でも cargo test が通る。本物の GitHub は呼ばない
  # The fake herdr and fake gh in tests/cli.rs are /bin/sh scripts using builtins only, so
  # `cargo test` runs inside the build sandbox without calling the real GitHub.
  doCheck = true;

  meta = with lib; {
    description = "herdr の各 agent の context 使用率と、決定者宛ての open のレビュー依頼を集める CLI";
    homepage = "https://github.com/music-brain88/dotfiles/tree/main/tools/herdr-ctx";
    license = licenses.mit;
    mainProgram = "herdr-ctx";
    platforms = platforms.linux;
  };
}
