# dotfiles

![Actions Status](https://github.com/music-brain88/dotfiles/workflows/build/badge.svg)

🚀 Overview / 概要

This repository contains my personal dotfiles and setup scripts for creating a modern, efficient development environment centered around
Neovim, Tmux, and Fish shell.

このリポジトリは、Neovim、Tmux、Fishシェルを中心に、モダンで効率的な開発環境を構築するための設定ファイル（dotfiles）とセットアップスクリプ
トをまとめたものです。

──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

📂 Directory Structure / ディレクトリ構造

```shell
dotfiles/
├── .backup/                 # Backup files / バックアップ関連ファイル
├── .bin/                    # Installation and deployment scripts (セットアップスクリプト群)
│   ├── deploy.sh            # Deploy dotfiles to home directory (dotfilesをホームディレクトリにデプロイ)
│   ├── install.sh           # Install required tools (必要なツールをインストール)
│   └── utils/               # Utility scripts for setup (各種ツールのセットアップスクリプト)
├── .config/                 # Configuration files for various tools (各種ツールの設定ファイル)
│   ├── alacritty/
│   ├── fish/
│   ├── hypr/
│   ├── i3/
│   ├── mpd/
│   ├── ncmpcpp/
│   ├── nvim/
│   ├── picom/
│   ├── polybar/
│   ├── rofi/
│   ├── starship/
│   └── waybar/
├── .github/                 # GitHub Actions workflows (GitHub Actionsの設定)
├── nix/                     # Nix configuration modules (Nix設定モジュール)
│   └── modules/             # Home Manager modules (Home Managerモジュール)
│       ├── base.nix         # Base packages (基本パッケージ)
│       ├── rust-tools.nix   # Rust development tools (Rust開発ツール)
│       ├── shell.nix        # Fish shell + Starship (Fishシェル + Starship)
│       ├── git.nix          # Git configuration (Git設定)
│       ├── tmux.nix         # Tmux configuration (Tmux設定)
│       ├── neovim.nix       # Neovim configuration (Neovim設定)
│       └── dev-tools.nix    # Development tools (開発ツール)
├── polybar-themes/          # Polybar themes (submodule) (Polybarテーマ（サブモジュール）)
├── flake.nix                # Nix flake configuration (Nix Flake設定)
├── home.nix                 # Home Manager main configuration (Home Managerメイン設定)
├── Dockerfile               # Dockerfile for containerized setup (Docker環境構築用ファイル)
├── LICENSE                  # MIT License (MITライセンス)
├── Makefile                 # Makefile for easy setup (簡単なセットアップ用Makefile)
├── README.md                # This document (本ドキュメント)
└── その他の設定ファイル (.bashrc, .gitconfigなど)
```

詳細な構造は [structure.md](structure.md) を参照してください。

---

## 🚩 Tech Stack / 技術スタック

- Editor (エディタ): Neovim (LSP, Treesitter, GitHub Copilot)
- Shell: Fish (Fisher plugin manager)
- Terminal Multiplexer: Tmux
- Window Managers: Hyprland (Wayland), i3 (X11)
- Status Bars: Waybar (Wayland), Polybar (X11)
- Launchers: Wofi (Wayland), Rofi (X11)
- Terminal Emulator: Alacritty
- CLI Tools: Rust-based tools (exa, ripgrep, fd, bat, gitui, delta, etc.)
- Prompt: Starship
- Containerization: Docker
- CI/CD: GitHub Actions

---

## 🚀 Installation (セットアップ方法)

⚠️ **Warning**: Review and modify these dotfiles before using. Use at your own risk.
⚠️ **注意**: 使用前に必ず内容を確認し、自己責任でご利用ください。

### 🎯 Two Setup Options (2つのセットアップ方法)

This repository supports two installation methods:
1. **Nix/Home Manager** (Recommended) - Declarative, reproducible setup
2. **Traditional Shell Scripts** - Legacy method using bash scripts

このリポジトリは2つのインストール方法をサポートしています:
1. **Nix/Home Manager** (推奨) - 宣言的で再現可能なセットアップ
2. **従来のシェルスクリプト** - bashスクリプトを使った従来の方法

---

### ✨ Option 1: Nix/Home Manager Setup (推奨)

#### Prerequisites (前提条件)
- Nix package manager (with flakes enabled)

#### Setup Steps (セットアップ手順)

**1. Install Nix (Nixをインストール)**

```shell
# Install Nix with flakes and nix-command enabled
sh <(curl -L https://nixos.org/nix/install) --daemon

# Or use the Determinate Systems installer (recommended)
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

**2. Clone the repository (リポジトリをクローン)**

```shell
git clone https://github.com/music-brain88/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

**3. Build and activate Home Manager configuration (Home Manager設定をビルド・アクティベート)**

```shell
# Build the configuration
nix build .#homeConfigurations.music-brain88.activationPackage

# Activate the configuration
./result/activate

# Or use a one-liner
nix run home-manager/master -- switch --flake .#music-brain88
```

**4. Install Neovim plugins (Neovimプラグインをインストール)**

```shell
nvim --headless +"call dein#install()" +qall
```

**Benefits of Nix/Home Manager:**
- ✅ Reproducible environment across machines
- ✅ Atomic upgrades and rollbacks
- ✅ Declarative configuration
- ✅ Automatic dependency management
- ✅ No manual tool installation required

**Nixのメリット:**
- ✅ マシン間で再現可能な環境
- ✅ アトミックなアップグレードとロールバック
- ✅ 宣言的な設定
- ✅ 自動的な依存関係管理
- ✅ 手動でのツールインストール不要

---

### 🔧 Option 2: Traditional Shell Script Setup

#### Prerequisites (前提条件)

- Neovim
- Tmux
- Fish Shell
- Make, GCC, pkg-config
- Rust (Cargo)
- Python (pyenv recommended)

#### Setup Steps (セットアップ手順)

1. Clone the repository (リポジトリをクローン):

```shell
git clone https://github.com/music-brain88/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

 2 Install required tools (必要なツールをインストール):

```shell
make install
```

 3 Deploy dotfiles (dotfilesをデプロイ):

```shell
make deploy
```

 4 Set up Python environment for Neovim (Python環境をセットアップ):


```shell
pyenv install <python3 version>
pyenv virtualenv <python3 version> neovim3
source ~/.pyenv/versions/neovim3/bin/activate.fish
pip install pynvim
```


 4 Install Neovim plugins (Neovimプラグインをインストール):


```neovim
:call dein#install()
```

──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
🐳 Docker Setup (Dockerを使ったセットアップ方法)

You can also set up the environment using Docker:

Dockerを使って環境を構築する場合は、以下の手順を実行します。

 1 Build Docker image (Dockerイメージをビルド):


```shell
make build
```

 2 Run Docker container (Dockerコンテナを起動):


```shell
make run
```

 3 Enter Docker container (Dockerコンテナに入る):


```shell
make exec
```

 4 Inside the container, install and deploy dotfiles (コンテナ内でdotfilesをインストール・デプロイ):


cd ~/dotfiles
make install
make deploy


──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

🛠️ Makefile Tasks (Makefileタスク一覧)

```shell
make install        # Install required tools (必要なツールをインストール)
make deploy         # Deploy dotfiles (dotfilesをデプロイ)
make update-tools    # Update Cargo tools (Cargoツールをアップデート)
make build           # Build Docker image (Dockerイメージをビルド)
make run             # Run Docker container (Dockerコンテナを起動)
make start           # Start Docker container (Dockerコンテナを開始)
make stop            # Stop Docker container (Dockerコンテナを停止)
make remove          # Remove Docker container (Dockerコンテナを削除)
make exec            # Execute bash in Docker container (Dockerコンテナ内でbashを実行)
make backup          # Backup Arch Linux packages (Arch Linuxのパッケージリストをバックアップ)
```


──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

📂 Directory Structure (ディレクトリ構造)

See structure.md for detailed directory structure.
詳細なディレクトリ構造は structure.md を参照してください。

──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

✨ Customization (カスタマイズ方法)

Feel free to fork and customize these dotfiles to suit your needs.
自由にフォークして、自分の好みに合わせてカスタマイズしてください。

──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

🤝 Contributing (コントリビューション)

Contributions are welcome! Feel free to submit issues or pull requests.
改善や機能追加の提案は大歓迎です！お気軽にIssueやPull Requestを送ってください。

──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

📜 License (ライセンス)

MIT License

──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

👤 Author (作者)

1saver (music-brain88)
