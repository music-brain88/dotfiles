{ config, pkgs, inputs, ... }:

{
  # CI-optimized Home Manager configuration
  # Minimal package set to reduce disk usage in GitHub Actions

  home.username = "archie";
  home.homeDirectory = "/home/archie";
  home.stateVersion = "24.05";

  programs.home-manager.enable = true;

  # Import only essential modules for CI testing
  imports = [
    ./nix/modules/base.nix
    ./nix/modules/rust-tools.nix
    ./nix/modules/shell.nix
    ./nix/modules/git.nix
    ./nix/modules/tmux.nix
    # Skip heavy modules in CI:
    # - neovim.nix (too many LSPs and tools)
    # - dev-tools.nix (Docker, cloud tools, databases)
  ];

  # Minimal Neovim setup for CI
  programs.neovim = {
    enable = true;
    package = pkgs.neovim-unwrapped;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;

    # Only essential packages for basic testing
    extraPackages = with pkgs; [
      # Just a few LSPs for validation
      lua-language-server
      nil

      # Minimal tooling
      tree-sitter
      gcc
      python311Packages.pynvim
    ];
  };

  # Environment variables
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  xdg.enable = true;
  xdg.configHome = "${config.home.homeDirectory}/.config";
  xdg.dataHome = "${config.home.homeDirectory}/.local/share";
  xdg.cacheHome = "${config.home.homeDirectory}/.cache";

  nixpkgs.config.allowUnfree = true;

  # Minimal file management for CI
  # Skip most dotfiles - just verify the structure works
  home.file = {
    ".bashrc".source = ./.bashrc;

    # Only essential config directories for testing
    ".config/nvim" = {
      source = ./.config/nvim;
      recursive = true;
    };

    ".config/fish" = {
      source = ./.config/fish;
      recursive = true;
    };
  };
}
