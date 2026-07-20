{ config, pkgs, inputs, ... }:

let
  # dpp.vim and its ecosystem (dein.vim successor, see #445/#471)
  # NOTE: Nix store (RO) is passed directly to runtimepath — no ~/.cache copy.
  #       This avoids the dein mtime-1970 trap (#466, Decision Log D4).
  # dpp.vim および周辺エコシステム(dein.vim の後継、#445/#471 参照)
  # 注: Nix store(RO)を直接 runtimepath に渡す — ~/.cache へのコピーはしない。
  #     dein の mtime 1970 罠(#466, Decision Log D4)の再発を構造的に防ぐ。
  #
  # None of these repos publish release tags (Shougo's plugins are rolling-release),
  # so revs are pinned to each repo's latest commit as of 2026-07-20 (see PR body for dates).
  # denops.vim is the exception: pinned to v8.0.2, satisfying dpp.vim's "denops v8+" requirement.
  # これらのリポジトリはリリースタグを持たない(Shougo系はローリングリリース運用)ため、
  # 2026-07-20 時点の各リポジトリ最新コミットに rev を固定した(日付は PR 本文参照)。
  # denops.vim のみ例外で v8.0.2 に固定 — dpp.vim が要求する「denops v8 以上」を満たす。
  dppVim = pkgs.fetchFromGitHub {
    owner = "Shougo";
    repo = "dpp.vim";
    rev = "ae4e9d926ba03deb1560ccd90bf88f3659ef1129";
    sha256 = "sha256-e7ofPE5Hziprom54QVHQHi9Xnh5vzVVt6OYZ+CKOGDI=";
  };

  denopsVim = pkgs.fetchFromGitHub {
    owner = "vim-denops";
    repo = "denops.vim";
    rev = "v8.0.2";
    sha256 = "sha256-lj8yjZrwE9GfNPDIpH4tCI4TTJHkYRlFFCTdqMqWtZg=";
  };

  dppExtInstaller = pkgs.fetchFromGitHub {
    owner = "Shougo";
    repo = "dpp-ext-installer";
    rev = "975ae45ac3d03935846481f2b978955817fcca50";
    sha256 = "sha256-2wORlA3QJ8pbUfDxpeFYA72+PjdbtLbjvjroP3KBR6I=";
  };

  dppExtLazy = pkgs.fetchFromGitHub {
    owner = "Shougo";
    repo = "dpp-ext-lazy";
    rev = "976fac445ff25acea7e2817b72f8c51ea0be648f";
    sha256 = "sha256-9HLDvHc1zZrWwxO445pdl3tNELBa9HLgERinVM6U0N8=";
  };

  dppExtToml = pkgs.fetchFromGitHub {
    owner = "Shougo";
    repo = "dpp-ext-toml";
    rev = "637e24781d49aeeb0e124b0a59e8587ab4621000";
    sha256 = "sha256-Uw4Huq8GQw5q7x6Y3VVKLTSlrAaVqXybBG1wYxA6BhI=";
  };

  dppProtocolGit = pkgs.fetchFromGitHub {
    owner = "Shougo";
    repo = "dpp-protocol-git";
    rev = "000f7ca2ad3264d7589e04d6a6c490fb3962185f";
    sha256 = "sha256-epg1tkSCuHQH7tttTnnEw1XbrZeL1f5t1ZScvHp1naA=";
  };
in
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
      # NOTE: nodePackages 名前空間は nixpkgs から廃止されたためトップレベル名で参照
      # The nodePackages namespace was removed from nixpkgs; use top-level names
      typescript-language-server
      vscode-langservers-extracted # HTML, CSS, JSON, ESLint
      yaml-language-server
      bash-language-server
      # NOTE: python3 (デフォルト版) を使うことでバイナリキャッシュに乗せる（3.11 指名はソースビルドに落ちる）
      # Use default python3 to hit cache.nixos.org; pinning 3.11 forces source builds
      python3Packages.python-lsp-server
      # NOTE: pyright は旧mason.nvim経由で供給されていたが、mason削除に伴いここで供給する(python-lsp-serverは別途Nix供給済みだがlsp_settings.tomlでは現状未使用)
      # pyright was previously supplied via mason.nvim; now supplied here after removing mason (python-lsp-server is also Nix-supplied but currently unused by lsp_settings.toml)
      pyright
      rust-analyzer
      gopls
      terraform-ls
      dockerfile-language-server
      marksman # Markdown LSP

      # Formatters
      stylua # Lua formatter
      nixpkgs-fmt # Nix formatter
      prettier # JS/TS/CSS/HTML formatter
      black # Python formatter
      rustfmt # Rust formatter
      shfmt # Shell script formatter

      # Linters
      shellcheck # Shell script linter
      statix # Nix linter
      eslint # JavaScript linter

      # Tree-sitter CLI
      tree-sitter

      # Debuggers
      lldb # For Rust, C, C++

      # Additional tools (not duplicated - others come from specialized modules)
      # ripgrep, fd: rust-tools.nix
      # fzf, gnumake, unzip, nodejs: dev-tools.nix
      # git: git.nix
      gcc # Compiler for some plugins

      # Python support for Neovim
      python3Packages.pynvim

      # Clipboard support
      wl-clipboard # Wayland
      xclip # X11 fallback: SSH X-forwarding / WSLg (デスクトップの X11 スタックは撤去済み)

      # denops.vim dependencies
      deno
    ];
  };

  # Install dein.vim (Neovim plugin manager used in existing config)
  # The existing TOML-based plugin configuration will continue to work
  home.file.".cache/dein" = {
    source = pkgs.fetchFromGitHub {
      owner = "Shougo";
      repo = "dein.vim";
      rev = "3.1";
      sha256 = "sha256-qKhuqDMkjvz7i79kHidiA0tlEl/ktPK5J8CfN74SzAM=";
    };
    recursive = true;
  };

  # Note: Python environment is managed in dev-tools.nix to avoid conflicts

  # Environment variables for Neovim
  home.sessionVariables = {
    # Point to Nix-managed Python
    NVIM_PYTHON3_HOST_PROG = "${pkgs.python3.withPackages (ps: [ ps.pynvim ])}/bin/python3";

    # dpp.vim store paths, exposed for init.lua (via vim.env) to read.
    # NOTE: dpp is installed but NOT wired into init.lua yet — dein remains
    #       the active plugin manager. Wiring is PR-2 (see #445/#471).
    # dpp.vim の store パス。init.lua 側が vim.env 経由で読める命名にしている。
    # 注: dpp は導入のみでまだ init.lua には配線していない — アクティブなプラグイン
    #     マネージャは引き続き dein。配線は PR-2(#445/#471 参照)で行う。
    NVIM_DPP_VIM = "${dppVim}";
    NVIM_DENOPS_VIM = "${denopsVim}";
    NVIM_DPP_EXT_INSTALLER = "${dppExtInstaller}";
    NVIM_DPP_EXT_LAZY = "${dppExtLazy}";
    NVIM_DPP_EXT_TOML = "${dppExtToml}";
    NVIM_DPP_PROTOCOL_GIT = "${dppProtocolGit}";
  };

  # Note: Existing Neovim configuration in .config/nvim/ is symlinked via home.nix
  # The TOML-based dein.vim setup remains unchanged for now
  # This provides a path for gradual migration to Nix-managed plugins if desired
}
