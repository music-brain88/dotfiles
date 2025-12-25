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
  home.file.".tmux.conf".source = ../../.tmux.conf;
}
