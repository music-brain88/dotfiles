{ config, pkgs, lib, ... }:

let
  # Runtime libraries for Playwright's downloaded Chromium on non-NixOS hosts.
  playwrightRuntimeLibs = with pkgs; [
    nss
    nspr
    alsa-lib
    atk
    at-spi2-atk
    cups
    dbus
    expat
    libdrm
    libxkbcommon
    libgbm
    gtk3
    glib
    pango
    cairo
    mesa
  ];
in

{
  # Development tools and utilities
  # Additional tools beyond base packages
  home.packages = with pkgs; [
    # Modern CLI tools
    fzf # Fuzzy finder
    jq # JSON processor
    yq # YAML processor
    httpie # HTTP client
    curl
    wget

    # Container tools
    docker
    docker-compose
    lazydocker # Docker TUI

    # Cloud tools
    awscli2 # AWS CLI
    google-cloud-sdk # Google Cloud SDK
    # kubectl / k9s / helm は nix/modules/k8s-tools.nix に集約
    # kubectl / k9s / helm moved to nix/modules/k8s-tools.nix (single owner)
    # NOTE: terraform は unfree (BUSL) でバイナリキャッシュに乗らないため OpenTofu を使用（コマンド名は tofu）
    # terraform is unfree (BUSL) and never cached by Hydra; use OpenTofu instead (command: tofu)
    opentofu # Infrastructure as code (Terraform-compatible)
    ansible # Configuration management

    # Database tools
    postgresql # PostgreSQL client
    mysql84 # MySQL client (8.4 LTS; mysql80 は 2026-04-30 EOL で nixpkgs から削除 / mysql80 removed from nixpkgs after its 2026-04-30 EOL)
    sqlite # SQLite

    # Language runtimes
    # 方針: Nix はベースライン提供のみ (バージョン指名しない = バイナリキャッシュに乗る)。
    # プロジェクトごとのバージョン固定は mise (各リポジトリの .mise.toml) で行う。
    # Policy: Nix provides baseline runtimes only (unpinned = cached by Hydra);
    # per-project versions are pinned via mise (.mise.toml in each repo).
    nodejs # Node.js
    python3 # Python
    # standalone-check: 配布文書の自立可読性チェッカー (tools/standalone-check、Rust、flake overlay で定義)。
    # standalone-report-writing skill の点検手順から呼ぶ。--with-yomiyasu は python3 で yomiyasu の lint を呼ぶ
    # In-repo Rust checker used by the standalone-report-writing skill; --with-yomiyasu shells out to python3
    standalone-check
    go # Go language
    ruby # Ruby
    php # PHP

    # Build tools
    gnumake
    cmake
    ninja
    meson

    # Browser test tools
    playwright-driver
    (writeShellScriptBin "playwright-with-deps" ''
      export LD_LIBRARY_PATH="${lib.makeLibraryPath playwrightRuntimeLibs}:''${LD_LIBRARY_PATH:-}"
      exec npx playwright "$@"
    '')

    # Version control
    git-crypt # Git encryption
    git-secret # Git secret management
    # gh is in git.nix

    # Secret management / パスワードマネージャCLI
    # bw: 公式CLI。添付ファイル対応 (GPG転送バンドルの push/fetch に使用 — mise gpg:* タスク)
    # rbw: Rust製agent方式クライアント。日常のシークレット取得向け
    bitwarden-cli # Official Bitwarden CLI (attachments support)
    rbw # Unofficial Rust Bitwarden client (agent-based)

    # Network tools
    nmap # Network scanner
    netcat # Network utility
    tcpdump # Packet analyzer
    wireshark # Network protocol analyzer
    mtr # Network diagnostic tool
    speedtest-cli # Internet speed test

    # System monitoring
    htop # Process viewer
    btop # Better top
    bottom # System monitor
    glances # System monitoring tool
    ncdu # Disk usage analyzer

    # Text processing
    gawk # GNU awk
    gnused # GNU sed
    gnugrep # GNU grep

    # PDF / document tools
    poppler-utils # pdftotext, pdftoppm, pdfinfo etc.

    # Compression tools
    # gzip is in base.nix
    p7zip # 7-Zip
    zip
    unzip
    bzip2
    xz

    # Formal methods
    tlaplus18 # TLA+ model checker (TLC) v1.8
    z3 # SMT solver — 純述語・設定系の検証用（python バインディング z3-solver は各プロジェクトの venv/uv 側で入れる方針）

    # Misc utilities
    screen # Terminal multiplexer
    direnv # Directory-based environment management
    asciinema # Terminal recorder
    fastfetch # System information (neofetch は上流メンテ停止で nixpkgs から削除 / neofetch removed from nixpkgs as unmaintained upstream)
    # tldr is provided by tealdeer in rust-tools.nix
  ];

  # FZF configuration
  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
    defaultCommand = "fd --type f";
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
      "--inline-info"
    ];
  };

  # Direnv configuration
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Mise (formerly rtx) - polyglot runtime manager
  # Replaces Volta for Node.js version management
  # NOTE: globalConfig でツールを指定しない — バージョンの source of truth は
  # 各プロジェクトの .mise.toml (ベースラインは上記 Language runtimes の Nix 側)
  # No globalConfig tools here: per-project .mise.toml is the source of truth
  # (baseline runtimes come from Nix above).
  programs.mise = {
    enable = true;
    enableFishIntegration = true;
  };

  # Zoxide - smarter cd command (alternative to z)
  # NOTE: enableFishIntegration は programs.fish を使わないハイブリッド方式では no-op なので false にする。
  # fish の z は nix/modules/shell.nix の fishPlugins.z (jethrokuan/z) が担っていて、
  # zoxide はフック未定義・DB 空で未使用 (パッケージだけ残す)。
  # enableFishIntegration is a no-op in this hybrid setup without programs.fish, so it is false.
  # fish's z comes from fishPlugins.z (jethrokuan/z) in nix/modules/shell.nix; zoxide has
  # no hook and an empty DB, so it is unused (only the package is kept).
  programs.zoxide = {
    enable = true;
    enableFishIntegration = false;
  };

  # Atuin - magical shell history
  # NOTE: enableFishIntegration は programs.fish が有効なときだけ init を注入する。
  # fish はネイティブの config.fish を symlink で配っているので、true にしても何もしない。
  # シェルフックは .config/fish/config.fish の `atuin init fish ... | source` で入れる。
  # programs.atuin 自体は settings (config.toml の生成) のために残す。
  # enableFishIntegration only injects init when programs.fish is enabled; fish is
  # configured via the symlinked native config.fish, so the hook lives there instead.
  # programs.atuin stays for generating config.toml from settings.
  programs.atuin = {
    enable = true;
    enableFishIntegration = false;
    settings = {
      auto_sync = true;
      sync_frequency = "5m";
      sync_address = "https://api.atuin.sh";
      search_mode = "fuzzy";
      # 秘密を含むコマンドを記録しない (履歴を LLM に渡す前段の防衛線、#710)
      # Keep secrets out of the history before it is ever handed to an LLM (#710)
      # NOTE: 正規表現にバックスラッシュを使わない (Nix 文字列 → TOML の二重エスケープを避ける)
      # No backslashes in the regexes, to avoid double escaping (Nix string -> TOML)
      secrets_filter = true;
      history_filter = [
        "^(export|set -[a-zA-Z]*x[a-zA-Z]*) .*(TOKEN|SECRET|PASSWORD|API_KEY)[A-Za-z0-9_]*[= ]"
        "^gh auth login --with-token"
        "^aws configure set aws_secret_access_key"
        "^atuin login"
        "^atuin register"
        "--passphrase"
      ];
    };
  };
}
