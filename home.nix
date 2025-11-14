{ config, pkgs, inputs, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should manage
  home.username = "music-brain88";
  home.homeDirectory = "/home/music-brain88";

  # This value determines the Home Manager release that your configuration is compatible with
  # You should not change this value, even if you update Home Manager
  home.stateVersion = "24.05";

  # Let Home Manager install and manage itself
  programs.home-manager.enable = true;

  # Import modular configurations
  imports = [
    ./nix/modules/base.nix
    ./nix/modules/rust-tools.nix
    ./nix/modules/shell.nix
    ./nix/modules/git.nix
    ./nix/modules/tmux.nix
    ./nix/modules/neovim.nix
    ./nix/modules/dev-tools.nix
  ];

  # Environment variables
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "firefox";
    TERMINAL = "alacritty";
  };

  # XDG base directories
  xdg.enable = true;
  xdg.configHome = "${config.home.homeDirectory}/.config";
  xdg.dataHome = "${config.home.homeDirectory}/.local/share";
  xdg.cacheHome = "${config.home.homeDirectory}/.cache";

  # Allow unfree packages (if needed)
  nixpkgs.config.allowUnfree = true;

  # Manage dotfiles with Home Manager
  # This allows symlinking configuration files
  home.file = {
    # Symlink Neovim config (keeping existing TOML-based setup)
    ".config/nvim" = {
      source = ./.config/nvim;
      recursive = true;
    };

    # Symlink Hyprland config
    ".config/hypr" = {
      source = ./.config/hypr;
      recursive = true;
    };

    # Symlink i3 config
    ".config/i3" = {
      source = ./.config/i3;
      recursive = true;
    };

    # Symlink Waybar config
    ".config/waybar" = {
      source = ./.config/waybar;
      recursive = true;
    };

    # Symlink Polybar config
    ".config/polybar" = {
      source = ./.config/polybar;
      recursive = true;
    };

    # Symlink Alacritty config
    ".config/alacritty" = {
      source = ./.config/alacritty;
      recursive = true;
    };
  };
}
