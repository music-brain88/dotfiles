{ config, pkgs, inputs, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should manage
  home.username = "archie";
  home.homeDirectory = "/home/archie";

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
    ./nix/modules/fonts.nix
  ];

  # Environment variables
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "firefox";
    TERMINAL = "alacritty";
    # SSL certificates (use system certs instead of Nix store)
    SSL_CERT_DIR = "/etc/ssl/certs";
    SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
  };

  # XDG base directories
  xdg.enable = true;
  xdg.configHome = "${config.home.homeDirectory}/.config";
  xdg.dataHome = "${config.home.homeDirectory}/.local/share";
  xdg.cacheHome = "${config.home.homeDirectory}/.cache";

  # Allow unfree packages (if needed)
  nixpkgs.config.allowUnfree = true;

  # Manage dotfiles with Home Manager
  # Symlinks matching deploy.sh
  home.file = {
    # Bash
    ".bashrc".source = ./.config/bash/bashrc;
    ".bash_profile".source = ./.config/bash/bash_profile;

    # Neovim config (keeping existing TOML-based setup)
    ".config/nvim" = {
      source = ./.config/nvim;
      recursive = true;
    };

    # Claude Code (directory-wide symlinks for commands support)
    ".claude" = {
      source = ./.config/claude;
      recursive = true;
    };
    # Make statusline-command.sh executable
    ".claude/statusline-command.sh" = {
      source = ./.config/claude/statusline-command.sh;
      executable = true;
    };

    # GitHub Copilot CLI (uses ~/.config/.copilot/)
    ".config/.copilot/config.json".source = ./.config/copilot/config.json;
    ".config/.copilot/copilot-instructions.md".source = ./.config/copilot/copilot-instructions.md;
    ".config/.copilot/skills" = {
      source = ./.config/copilot/skills;
      recursive = true;
    };
    # Global copilot-instructions for GitHub Copilot (VS Code, etc.)
    ".github/copilot-instructions.md".source = ./.config/copilot/copilot-instructions.md;

    # Hyprland config
    ".config/hypr" = {
      source = ./.config/hypr;
      recursive = true;
    };

    # i3 config
    ".config/i3" = {
      source = ./.config/i3;
      recursive = true;
    };

    # Waybar config
    ".config/waybar" = {
      source = ./.config/waybar;
      recursive = true;
    };

    # Polybar config
    ".config/polybar" = {
      source = ./.config/polybar;
      recursive = true;
    };

    # Alacritty config
    ".config/alacritty" = {
      source = ./.config/alacritty;
      recursive = true;
    };

    # Rofi config
    ".config/rofi" = {
      source = ./.config/rofi;
      recursive = true;
    };

    # Wofi config
    ".config/wofi" = {
      source = ./.config/wofi;
      recursive = true;
    };

    # Mako config
    ".config/mako" = {
      source = ./.config/mako;
      recursive = true;
    };

    # MPD config
    ".config/mpd" = {
      source = ./.config/mpd;
      recursive = true;
    };

    # EWW config
    ".config/eww" = {
      source = ./.config/eww;
      recursive = true;
    };

    # ncmpcpp config
    ".config/ncmpcpp" = {
      source = ./.config/ncmpcpp;
      recursive = true;
    };

    # fontconfig
    ".config/fontconfig" = {
      source = ./.config/fontconfig;
      recursive = true;
    };
  };
}
