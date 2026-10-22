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
    ./nix/modules/k8s-tools.nix
    ./nix/modules/fonts.nix
  ]
  ++ lib.optionals (profile == "native") [
    ./nix/modules/desktop.nix
    # WSL 機では kitty graphics を描画できないので native 機だけ (Issue #701)
    # Native only: WSL can't render kitty graphics (Issue #701)
    ./nix/modules/terminal-browser.nix
  ]
  ++ lib.optionals (profile == "wsl") [ ./nix/modules/wsl.nix ];

  # Environment variables
  home.sessionVariables = let caBundle = "/etc/ssl/certs/ca-certificates.crt"; in {
    EDITOR = "nvim";
    VISUAL = "nvim";
    # device-auth 系 CLI (aws sso login / gh auth login -w / gcloud auth login 等) の
    # 承認 URL を、herdr の中では terminal-browser の pane に開くラッパー。herdr 外では
    # 内部で GUI ブラウザ (xdg-open 等) にフォールバックする (Issue #523, #701)。
    # Opens device-auth approval URLs in a terminal-browser pane inside herdr; falls
    # back to the GUI browser internally outside herdr (Issue #523, #701).
    BROWSER = "${config.home.homeDirectory}/.local/bin/device_auth_browser";
    TERMINAL = "wezterm";
    # CA の信頼判断は、OS 層の ca-certificates-mozilla(pacman)が作るシステムの信頼ストア 1 本に寄せる。
    # OpenSSL を使うツール(curl / git / python / go / mise / rustup / uv)は SSL_CERT_FILE を読む。
    # 自前のルート束を同梱するランタイムは SSL_CERT_FILE を読まないので、ツール固有の変数で同じ束を指す。
    # 各変数の効果は checker ホストで実測した(Issue #738、手順は docs/how-to/verify-ca-trust-stores.md)。
    # CA trust decisions are delegated to the system trust store built by pacman's
    # ca-certificates-mozilla. OpenSSL-based tools honor SSL_CERT_FILE; runtimes that bundle
    # their own root store ignore it, so each gets a tool-specific variable pointing at the
    # same bundle. Every variable was verified against the checker hosts (Issue #738, see
    # docs/how-to/verify-ca-trust-stores.md).
    SSL_CERT_DIR = "/etc/ssl/certs";
    SSL_CERT_FILE = caBundle;
    # node(mise): 同梱の束を捨てて OpenSSL の束に置き換える(--use-system-ca は追加モードなので効かない)
    # node (mise): replace the bundled roots with OpenSSL's store (--use-system-ca only appends)
    NODE_OPTIONS = "--use-openssl-ca";
    # deno(cargo): rustls に OS の束を読ませる / deno (cargo): make rustls read the OS store
    DENO_TLS_CA_STORE = "system";
    # awscli(mise)と requests を使う Python ツール(poetry など)は同梱の certifi を読むので束のパスを渡す
    # awscli (mise) and requests-based Python tools (poetry etc.) ship certifi; hand them the bundle path
    AWS_CA_BUNDLE = caBundle;
    REQUESTS_CA_BUNDLE = caBundle;
    # gcloud(Nix): 同梱の certifi の代わりに読む束 / gcloud (Nix): bundle read instead of its vendored certifi
    CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE = caBundle;
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
    ".claude/skills/learn" = { source = ./.config/skills/learn; recursive = true; };
    ".claude/skills/distill" = { source = ./.config/skills/distill; recursive = true; };
    ".claude/skills/digest" = { source = ./.config/skills/digest; recursive = true; };
    ".claude/skills/cognitive-rhythm-writing" = { source = ./.config/skills/cognitive-rhythm-writing; recursive = true; };
    ".claude/skills/japanese-tech-writing" = { source = ./.config/skills/japanese-tech-writing; recursive = true; };
    ".claude/skills/standalone-report-writing" = { source = ./.config/skills/standalone-report-writing; recursive = true; };
    ".claude/skills/yomiyasu" = { source = ./.config/skills/yomiyasu; recursive = true; };

    # mise global config (tools available outside project dirs; claude is NOT here — it uses its native installer)
    # mise グローバル設定（プロジェクト外でも使うツール。claude は native installer 管理で node 経由ではない）
    # force: overwrite real files created by `mise use -g` so activation never stalls
    # force: `mise use -g` が作る実ファイルを上書きして activation の停止を防ぐ
    ".config/mise/config.toml" = {
      source = ./.config/mise/config.toml;
      force = true;
    };

    # GitHub Copilot CLI (uses ~/.copilot/)
    # NOTE: ~/.copilot/config.json (auth/trustedFolders, auto-managed) and
    # ~/.copilot/settings.json (user settings, written by /model and /settings)
    # are intentionally left unmanaged by Nix (Issue #597)
    # config.json は CLI の自動管理ファイル、settings.json は /model や /settings が
    # 書き換えるユーザー設定のため、どちらも Nix 管理外(CLI 任せ)とする
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
    ".copilot/skills/learn" = { source = ./.config/skills/learn; recursive = true; };
    ".copilot/skills/distill" = { source = ./.config/skills/distill; recursive = true; };
    ".copilot/skills/digest" = { source = ./.config/skills/digest; recursive = true; };
    ".copilot/skills/cognitive-rhythm-writing" = { source = ./.config/skills/cognitive-rhythm-writing; recursive = true; };
    ".copilot/skills/japanese-tech-writing" = { source = ./.config/skills/japanese-tech-writing; recursive = true; };
    ".copilot/skills/standalone-report-writing" = { source = ./.config/skills/standalone-report-writing; recursive = true; };
    ".copilot/skills/yomiyasu" = { source = ./.config/skills/yomiyasu; recursive = true; };
    # Global copilot-instructions for GitHub Copilot (VS Code, etc.)
    ".github/copilot-instructions.md".source = ./.config/copilot/copilot-instructions.md;

    # GUI 系 (hypr / waybar / alacritty / wofi / mako / mpd / ncmpcpp / fontconfig /
    # systemd user units) は nix/modules/desktop.nix へ移動 (native profile のみ)
    # GUI configs moved to nix/modules/desktop.nix (native profile only)
  };
}
