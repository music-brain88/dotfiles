{ config, pkgs, ... }:

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
    terraform # Infrastructure as code
    ansible # Configuration management

    # Database tools
    postgresql # PostgreSQL client
    mysql80 # MySQL client
    sqlite # SQLite

    # Language runtimes
    nodejs_20 # Node.js
    python311 # Python 3.11
    go # Go language
    ruby # Ruby
    php # PHP

    # Build tools
    gnumake
    cmake
    ninja
    meson

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

    # Compression tools
    p7zip # 7-Zip
    zip
    unzip
    gzip
    bzip2
    xz

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
  programs.mise = {
    enable = true;
    enableFishIntegration = true;

    settings = {
      tools = {
        node = "lts";
        python = "3.11";
      };
    };
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
