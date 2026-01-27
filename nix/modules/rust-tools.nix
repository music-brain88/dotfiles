{ config, pkgs, ... }:

{
  # Rust development environment and CLI tools
  # Replaces setup_rust_tools.sh functionality
  home.packages = with pkgs; [
    # Rust toolchain (cargo is included in rustup)
    rustup
    cargo-update

    # Build dependencies for native crates (openssl-sys, etc.)
    openssl.dev
    pkg-config

    # Modern Unix tools written in Rust
    fd # fd-find - fast alternative to find
    ripgrep # rg - fast grep alternative
    eza # modern replacement for ls
    bat # cat with syntax highlighting
    procs # modern replacement for ps
    gitui # terminal UI for git
    tealdeer # tldr client
    hyperfine # command-line benchmarking tool
    dust # disk usage analyzer
    tokei # code statistics tool
    jql # JSON query language
    oxker # Docker TUI
    skim # Command-line fuzzy finder
  ];

  # Environment variables for Rust
  home.sessionVariables = {
    CARGO_HOME = "${config.home.homeDirectory}/.cargo";
    RUSTUP_HOME = "${config.home.homeDirectory}/.rustup";
    # pkg-config search path for native crates
    PKG_CONFIG_PATH = "${config.home.homeDirectory}/.nix-profile/lib/pkgconfig";
  };

  # Add Cargo bin to PATH
  home.sessionPath = [
    "${config.home.homeDirectory}/.cargo/bin"
  ];
}
