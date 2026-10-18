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

  # device-auth 承認 URL を、herdr の中では terminal-browser の pane に開く $BROWSER ラッパー
  # (Issue #523, #701)。terminal-browser は native 機だけに入る (nix/modules/terminal-browser.nix)。
  # 見つからない機械ではラッパーが GUI ブラウザへフォールバックする。
  # $BROWSER wrapper that opens device-auth approval URLs in a terminal-browser pane inside
  # herdr (Issue #523, #701). terminal-browser is installed on the native machine only
  # (nix/modules/terminal-browser.nix); elsewhere the wrapper falls back to the GUI browser.
  home.file.".local/bin/device_auth_browser" = {
    source = ../../.config/herdr/scripts/device_auth_browser.sh;
    executable = true;
  };
}
