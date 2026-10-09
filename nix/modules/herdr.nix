{ config, pkgs, ... }:

{
  # herdr - agent multiplexer (tmux の後継 / successor to tmux)
  # pkgs.herdr は flake.nix の overlay 経由で新しい nixpkgs から供給される
  # pkgs.herdr comes from a newer nixpkgs pin via the overlay in flake.nix
  home.packages = with pkgs; [
    herdr
  ];

  # herdr config symlink (keybind は旧 tmux 設定互換 / tmux-compatible keybindings)
  home.file.".config/herdr/config.toml".source = ../../.config/herdr/config.toml;

  # device-auth 承認 URL を herdr-browser pane に直行させる $BROWSER ラッパー (Issue #523)
  # $BROWSER wrapper that routes device-auth approval URLs into a herdr-browser pane (Issue #523)
  home.file.".local/bin/device_auth_browser" = {
    source = ../../.config/herdr/scripts/device_auth_browser.sh;
    executable = true;
  };

  # herdr v0.9.2 で herdr 固有の pane graphics API (pane.graphics.*) が廃止された。
  # herdr-browser の viewer は既定でこの API を順に呼んで失敗し、警告 3 行を出してから
  # 標準の Kitty graphics を pane の PTY に直接書く経路に落ちる。direct-kitty を指定して
  # 最初からその経路で描画させる。herdr サーバーの環境を継承するので、変更後は
  # herdr サーバーの再起動が要る (Issue #693)。
  # herdr v0.9.2 removed the herdr-specific pane graphics API (pane.graphics.*).
  # By default the herdr-browser viewer calls it, fails with three warnings, and then
  # falls back to writing standard Kitty graphics to the pane PTY. direct-kitty makes
  # it use that path from the start. The viewer inherits the herdr server's
  # environment, so restart the herdr server after changing this (Issue #693).
  home.sessionVariables = {
    HERDR_BROWSER_TRANSPORT = "direct-kitty";
  };
}
