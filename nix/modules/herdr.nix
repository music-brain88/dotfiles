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

  # herdr 公式の Claude Code 用フック (Issue #755)。スクリプトは flake.nix の overlay が
  # ビルド時に公式インストーラで生成する (pkgs.herdr-claude-hook)。呼び出すエントリは
  # .config/claude/settings.json の SessionStart に手書きしてあり、ずれは
  # checks.herdr-claude-hook-entries (`mise run nix:check`) が見つける。
  # home.nix の ".claude" の recursive マウントの下に、statusline-command.sh と同じ形の個別エントリで足す。
  # .config/claude/ には hooks/ が無いので、recursive マウントとは衝突しない。
  # herdr's official Claude Code hook (Issue #755). The overlay in flake.nix generates the
  # script with the official installer at build time (pkgs.herdr-claude-hook). The entry that
  # calls it is hand-written under SessionStart in .config/claude/settings.json, and
  # checks.herdr-claude-hook-entries (`mise run nix:check`) catches drift between the two.
  # Added under the recursive ".claude" mount in home.nix as an individual entry, same pattern
  # as statusline-command.sh. .config/claude/ has no hooks/, so it does not collide with the mount.
  home.file.".claude/hooks/herdr-agent-state.sh".source =
    "${pkgs.herdr-claude-hook}/hooks/herdr-agent-state.sh";

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
