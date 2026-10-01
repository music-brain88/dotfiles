# standalone-check: 配布文書の自立可読性を点検する CLI(Rust)。
# flake.nix の overlay から callPackage され、nix/modules/dev-tools.nix の home.packages で配る。
# Built via overlay in flake.nix and shipped through home.packages (dev-tools.nix).
{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "standalone-check";
  version = "0.1.0";

  src = lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;

  # tests/fixtures の偽 lint は /bin/sh スクリプトなので、ビルドサンドボックス内でも cargo test が通る
  # Fixture fakes are /bin/sh scripts, so `cargo test` runs inside the build sandbox without python3.
  doCheck = true;

  meta = with lib; {
    description = "配布文書の自立可読性を機械的に点検する CLI (standalone-report-writing skill の点検ツール)";
    homepage = "https://github.com/music-brain88/dotfiles/tree/main/tools/standalone-check";
    license = licenses.mit;
    mainProgram = "standalone-check";
    platforms = platforms.linux;
  };
}
