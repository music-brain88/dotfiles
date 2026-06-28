{ config, pkgs, ... }:

{
  # Git - packages only, config via symlinks
  home.packages = with pkgs; [
    git
    git-lfs
    delta
    gh
    gh-dash
    github-copilot-cli # GitHub Copilot CLI (agentic terminal assistant)
    gnupg
  ];

  # Git config symlinks (matching deploy.sh)
  home.file.".gitconfig".source = ../../.config/git/config;
  xdg.configFile."git/ignore".source = ../../.config/git/ignore;

  # GnuPG config symlink (gpg-agent cache TTL)
  home.file.".gnupg/gpg-agent.conf".source = ../../.config/gnupg/gpg-agent.conf;

  # GnuPG expects a private home directory.
  # GnuPGは ~/.gnupg がprivateじゃないと警告する
  home.activation.ensureGnuPGHomePermissions = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.gnupg"
    chmod 700 "$HOME/.gnupg"
  '';
}
