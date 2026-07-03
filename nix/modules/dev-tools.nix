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
    kubectl # Kubernetes CLI
    k9s # Kubernetes TUI
    helm # Kubernetes package manager
    # NOTE: terraform は unfree (BUSL) でバイナリキャッシュに乗らないため OpenTofu を使用（コマンド名は tofu）
    # terraform is unfree (BUSL) and never cached by Hydra; use OpenTofu instead (command: tofu)
    opentofu # Infrastructure as code (Terraform-compatible)
    ansible # Configuration management

    # Database tools
    postgresql # PostgreSQL client
    mysql80 # MySQL client
    sqlite # SQLite

    # Language runtimes
    # 方針: Nix はベースライン提供のみ (バージョン指名しない = バイナリキャッシュに乗る)。
    # プロジェクトごとのバージョン固定は mise (各リポジトリの .mise.toml) で行う。
    # Policy: Nix provides baseline runtimes only (unpinned = cached by Hydra);
    # per-project versions are pinned via mise (.mise.toml in each repo).
    nodejs # Node.js
    python3 # Python
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
    neofetch # System information
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
  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  # Atuin - magical shell history
  programs.atuin = {
    enable = true;
    enableFishIntegration = true;
    settings = {
      auto_sync = true;
      sync_frequency = "5m";
      sync_address = "https://api.atuin.sh";
      search_mode = "fuzzy";
    };
  };
}
