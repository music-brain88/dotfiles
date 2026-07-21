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
    TERMINAL = "wezterm";
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

    # Claude Code (directory-wide symlinks for skills support)
    ".claude" = {
      source = ./.config/claude;
      recursive = true;
    };
    # Make statusline-command.sh executable
    ".claude/statusline-command.sh" = {
      source = ./.config/claude/statusline-command.sh;
      executable = true;
    };

    # Tool-neutral shared skills (single source of truth, see .config/skills/)
    # Claude / Copilot 共有スキル(単一ソース。ドリフト防止 — Issue #404)
    # Individual per-skill entries override the recursive ".claude" mount above,
    # same pattern as statusline-command.sh. There is no recursive ".copilot/skills"
    # mount to override below — Copilot has no skills of its own, so each shared
    # skill is mounted directly (see the ".copilot/skills/*" entries further down).
    # 上記の ".claude" recursive マウントを個別スキルごとに上書きする(statusline-command.sh と同じパターン)。
    # ".copilot/skills" 側は上書き対象となる recursive マウント自体が存在しない
    # (Copilot 固有のスキルを持たないため、共有スキルを個別に直接マウントするのみ。後述の ".copilot/skills/*" 参照)
    ".claude/skills/context" = { source = ./.config/skills/context; recursive = true; };
    ".claude/skills/create-issue" = { source = ./.config/skills/create-issue; recursive = true; };
    ".claude/skills/pr" = { source = ./.config/skills/pr; recursive = true; };
    ".claude/skills/release-note" = { source = ./.config/skills/release-note; recursive = true; };
    ".claude/skills/formal" = { source = ./.config/skills/formal; recursive = true; };
    ".claude/skills/daily" = { source = ./.config/skills/daily; recursive = true; };
    ".claude/skills/session-log" = { source = ./.config/skills/session-log; recursive = true; };
    ".claude/skills/herdr-chat" = { source = ./.config/skills/herdr-chat; recursive = true; };
    ".claude/skills/qbq" = { source = ./.config/skills/qbq; recursive = true; };

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
    # Tool-neutral shared skills, same source as ".claude/skills/*" above (Issue #404)
    # Claude 側と同じソースを共有(単一ソース化)
    ".copilot/skills/context" = { source = ./.config/skills/context; recursive = true; };
    ".copilot/skills/create-issue" = { source = ./.config/skills/create-issue; recursive = true; };
    ".copilot/skills/pr" = { source = ./.config/skills/pr; recursive = true; };
    ".copilot/skills/release-note" = { source = ./.config/skills/release-note; recursive = true; };
    ".copilot/skills/formal" = { source = ./.config/skills/formal; recursive = true; };
    ".copilot/skills/daily" = { source = ./.config/skills/daily; recursive = true; };
    ".copilot/skills/session-log" = { source = ./.config/skills/session-log; recursive = true; };
    ".copilot/skills/herdr-chat" = { source = ./.config/skills/herdr-chat; recursive = true; };
    ".copilot/skills/qbq" = { source = ./.config/skills/qbq; recursive = true; };
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
