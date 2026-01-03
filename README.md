# dotfiles

![Actions Status](https://github.com/music-brain88/dotfiles/workflows/build/badge.svg)

## 🚀 Overview / 概要

Modern, declarative development environment using **Nix + Home Manager + mise**.

Nix + Home Manager + mise を使用した、宣言的でモダンな開発環境です。

---

## 🛠️ Tech Stack / 技術スタック

| Category | Tools |
|----------|-------|
| Editor | Neovim (LSP, Treesitter, GitHub Copilot) |
| Shell | Fish + Starship |
| Terminal | Alacritty |
| Multiplexer | Tmux |
| Window Manager | Hyprland (Wayland), i3 (X11) |
| Status Bar | Waybar (Wayland), Polybar (X11) |
| CLI Tools | Rust-based (eza, ripgrep, fd, bat, delta, etc.) |
| Package Manager | Nix + Home Manager |
| Task Runner | mise |

---

## ⚡ Quick Start / クイックスタート

### 1. Install Nix

```bash
# Determinate Systems Installer (推奨)
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

### 2. Clone & Setup

```bash
git clone https://github.com/music-brain88/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Build and activate
mise run nix:switch

# Install Neovim plugins
nvim --headless +"call dein#install()" +qall
```

> 📖 詳細は [docs/NIX.md](docs/NIX.md) を参照してください。

---

## 📋 Task Runner (mise)

よく使うコマンドを `mise` タスクとして定義しています。

```bash
# タスク一覧を表示
mise tasks
```

### Nix Tasks

| Task | Description |
|------|-------------|
| `mise run nix:build` | Home Manager 設定をビルド |
| `mise run nix:switch` | ビルド＆アクティベート |
| `mise run nix:check` | Flake チェック実行 |
| `mise run nix:update` | Flake inputs を更新 |
| `mise run nix:gc` | ガベージコレクト |

### Docker Tasks

| Task | Description |
|------|-------------|
| `mise run docker:build` | Docker イメージをビルド |
| `mise run docker:run` | コンテナを起動 |
| `mise run docker:exec` | コンテナ内で bash 実行 |
| `mise run docker:stop` | コンテナを停止 |
| `mise run docker:remove` | コンテナを削除 |

### Utility Tasks

| Task | Description |
|------|-------------|
| `mise run backup` | Arch Linux パッケージリストをバックアップ |

---

## 🐳 Docker Setup

```bash
# Build and run
mise run docker:build
mise run docker:run

# Enter container
mise run docker:exec
```

---

## 📂 Directory Structure

```
dotfiles/
├── .config/          # Application configurations
├── docs/             # Documentation
├── nix/modules/      # Nix modules
├── .mise.toml        # Task definitions
├── flake.nix         # Nix Flake entry point
└── home.nix          # Home Manager config
```

> 📖 詳細は [docs/STRUCTURE.md](docs/STRUCTURE.md) を参照してください。

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | アーキテクチャ設計・設計思想 |
| [docs/NIX.md](docs/NIX.md) | Nix/Home Manager 詳細ガイド |
| [docs/KEYBINDINGS.md](docs/KEYBINDINGS.md) | キーバインド・ショートカット一覧 |
| [docs/NEOVIM.md](docs/NEOVIM.md) | Neovim 設定ガイド |
| [docs/STRUCTURE.md](docs/STRUCTURE.md) | ディレクトリ構造の詳細 |
| [docs/WORKFLOW.md](docs/WORKFLOW.md) | 作業ワークフロー・よく使うコマンド |
| [CLAUDE.md](CLAUDE.md) | Claude Code 向けコンテキスト |

> 📖 詳細は [docs/README.md](docs/README.md) を参照してください。

---

## ✨ Customization / カスタマイズ

Fork して自分の環境に合わせてカスタマイズしてください。

```nix
# home.nix を編集
home.username = "your-username";
home.homeDirectory = "/home/your-username";
```

---

## 🤝 Contributing

Contributions are welcome! / 改善や機能追加の提案は大歓迎です！

1. Fork this repository
2. Create feature branch
3. Make your changes
4. Submit pull request

---

## 📜 License

MIT License

---

## 👤 Author

1saver (music-brain88)
