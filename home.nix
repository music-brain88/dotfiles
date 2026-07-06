{ config, pkgs, lib, inputs, profile, ... }:

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
  # profile ("native" | "wsl") は flake.nix の extraSpecialArgs から渡される
  # profile ("native" | "wsl") comes from extraSpecialArgs in flake.nix
  imports = [
    ./nix/modules/base.nix
    ./nix/modules/rust-tools.nix
    ./nix/modules/shell.nix
    ./nix/modules/git.nix
    ./nix/modules/tmux.nix # 併存期間中: herdr 移行完了後に削除予定 / kept during herdr migration
    ./nix/modules/herdr.nix
    ./nix/modules/neovim.nix
    ./nix/modules/dev-tools.nix
    ./nix/modules/fonts.nix
  ]
  ++ lib.optionals (profile == "native") [ ./nix/modules/desktop.nix ]
  ++ lib.optionals (profile == "wsl") [ ./nix/modules/wsl.nix ];

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

    # mise global config (tools available outside project dirs, e.g. claude via node)
    # mise グローバル設定（プロジェクト外でも使うツール。claude は node 経由）
    # force: overwrite real files created by `mise use -g` so activation never stalls
    # force: `mise use -g` が作る実ファイルを上書きして activation の停止を防ぐ
    ".config/mise/config.toml" = {
      source = ./.config/mise/config.toml;
      force = true;
    };

    # GitHub Copilot CLI (uses ~/.copilot/)
    # NOTE: config.json is seeded via activation script (Copilot CLI writes to it dynamically)
    ".copilot/copilot-instructions.md".source = ./.config/copilot/copilot-instructions.md;
    ".copilot/skills" = {
      source = ./.config/copilot/skills;
      recursive = true;
    };
    # Global copilot-instructions for GitHub Copilot (VS Code, etc.)
    ".github/copilot-instructions.md".source = ./.config/copilot/copilot-instructions.md;

    # GUI 系 (hypr / waybar / alacritty / wofi / mako / mpd / ncmpcpp / fontconfig /
    # systemd user units) は nix/modules/desktop.nix へ移動 (native profile のみ)
    # GUI configs moved to nix/modules/desktop.nix (native profile only)
  };

  # Activation scripts for files that need to be writable at runtime
  home.activation.seedCopilotConfig = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    target="$HOME/.copilot/config.json"
    if [ ! -f "$target" ] || [ -L "$target" ]; then
      mkdir -p "$(dirname "$target")"
      rm -f "$target"
      cp ${./.config/copilot/config.json} "$target"
      chmod 644 "$target"
    fi
  '';
}
