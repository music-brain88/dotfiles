{ config, pkgs, inputs, ... }:

{
  # Neovim configuration
  # This module manages Neovim installation and dependencies
  # The actual plugin configuration remains in TOML files as per existing setup

  programs.neovim = {
    enable = true;

    # Use latest stable or nightly Neovim
    package = pkgs.neovim-unwrapped;

    # Set as default editor
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;

    # Additional packages available to Neovim
    extraPackages = with pkgs; [
      # Language servers (LSP)
      lua-language-server
      nil # Nix LSP
      nodePackages.typescript-language-server
      nodePackages.vscode-langservers-extracted # HTML, CSS, JSON, ESLint
      nodePackages.yaml-language-server
      nodePackages.bash-language-server
      python311Packages.python-lsp-server
      rust-analyzer
      gopls
      terraform-ls
      dockerfile-language-server-nodejs
      marksman # Markdown LSP

      # Formatters
      stylua # Lua formatter
      nixpkgs-fmt # Nix formatter
      nodePackages.prettier # JS/TS/CSS/HTML formatter
      black # Python formatter
      rustfmt # Rust formatter
      shfmt # Shell script formatter

      # Linters
      shellcheck # Shell script linter
      statix # Nix linter
      nodePackages.eslint # JavaScript linter

      # Tree-sitter CLI
      tree-sitter

      # Debuggers
      lldb # For Rust, C, C++

      # Additional tools
      ripgrep # For telescope.nvim
      fd # For telescope.nvim
      fzf # Fuzzy finder
      git # Required for various plugins
      gnumake # For building plugins
      gcc # Compiler for some plugins
      unzip # For unpacking plugins

      # Python support for Neovim
      python311Full
      python311Packages.pynvim

      # Node.js support
      nodejs_20

      # Clipboard support
      wl-clipboard # Wayland
      xclip # X11
    ];
  };

  # Install dein.vim (Neovim plugin manager used in existing config)
  # The existing TOML-based plugin configuration will continue to work
  home.file.".cache/dein" = {
    source = pkgs.fetchFromGitHub {
      owner = "Shougo";
      repo = "dein.vim";
      rev = "v3.0";
      sha256 = "sha256-4LHf3bq7PLpc7Nm9sg6eTfMTWPFWx8nJ3r3AC+0YYxI=";
    };
    recursive = true;
  };

  # Python environment for Neovim
  # This replaces the manual pyenv setup from CLAUDE.md
  home.packages = with pkgs; [
    # Python virtual environment for Neovim
    (python311.withPackages (ps: with ps; [
      pynvim
      python-lsp-server
      pylint
      flake8
      black
      isort
    ]))
  ];

  # Environment variables for Neovim
  home.sessionVariables = {
    # Point to Nix-managed Python
    NVIM_PYTHON3_HOST_PROG = "${pkgs.python311.withPackages (ps: [ ps.pynvim ])}/bin/python3";
  };

  # Note: Existing Neovim configuration in .config/nvim/ is symlinked via home.nix
  # The TOML-based dein.vim setup remains unchanged for now
  # This provides a path for gradual migration to Nix-managed plugins if desired
}
