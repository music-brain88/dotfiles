{ config, pkgs, ... }:

{
  # Git - packages only, config via symlinks
  home.packages = with pkgs; [
    git
    git-lfs
    delta
    gh
    gh-dash
    gh-copilot
  ];

  # Git config symlinks (matching deploy.sh)
  home.file.".gitconfig".source = ../../.gitconfig;
  xdg.configFile."git/ignore".source = ../../.config/git/ignore;
}
