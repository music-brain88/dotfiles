{ config, pkgs, ... }:

{
  # Tmux - packages only, config via symlinks
  home.packages = with pkgs; [
    tmux
    tmuxPlugins.sensible
    tmuxPlugins.yank
    tmuxPlugins.resurrect
    tmuxPlugins.continuum
    tmuxPlugins.vim-tmux-navigator
  ];

  # Tmux config symlink (matching deploy.sh)
  home.file.".tmux.conf".source = ../../.config/tmux/tmux.conf;

  # Claude Code popup launcher (per-directory persistent session)
  # ~/.local/bin is already on PATH; tmux.conf binds it to prefix + C.
  home.file.".local/bin/tmux-claude-popup" = {
    source = ../../.config/tmux/scripts/tmux-claude-popup;
    executable = true;
  };
}
