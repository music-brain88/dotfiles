# dotfiles

[![CI](https://img.shields.io/github/actions/workflow/status/music-brain88/dotfiles/nix.yml?branch=main&label=CI&logo=github)](https://github.com/music-brain88/dotfiles/actions/workflows/nix.yml)
[![Docker](https://img.shields.io/badge/Docker-Build-2496ED?logo=docker&logoColor=white)](https://github.com/music-brain88/dotfiles/pkgs/container/dotfiles%2Fdotfiles-env)
[![Nix](https://img.shields.io/badge/Nix-Flake-5277C3?logo=nixos&logoColor=white)](https://nixos.org)
[![Arch Linux](https://img.shields.io/badge/Arch%20Linux-Verified-1793D1?logo=archlinux&logoColor=white)](https://archlinux.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

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

```bash
# Install Nix (Determinate Systems Installer, 推奨)
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# Clone & activate
git clone https://github.com/music-brain88/dotfiles.git ~/dotfiles
cd ~/dotfiles
mise run nix:switch
```

> 📖 ステップバイステップの解説は [docs/tutorials/getting-started.md](docs/tutorials/getting-started.md) を参照してください。

---

## 📋 Task Runner (mise)

よく使うコマンドを `mise` タスクとして定義しています。

```bash
# タスク一覧を表示
mise tasks
```

> 📖 全タスクの一覧は [docs/reference/mise-tasks.md](docs/reference/mise-tasks.md) を参照してください。

---

## 🐳 Docker Setup

```bash
# Build and run
mise run docker:build
mise run docker:run
```

> 📖 詳細は [docs/how-to/run-with-docker.md](docs/how-to/run-with-docker.md) を参照してください。

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

> 📖 詳細は [docs/reference/directory-structure.md](docs/reference/directory-structure.md) を参照してください。

---

## 📚 Documentation

ドキュメントは [Diátaxis](https://diataxis.fr) に沿って4つに分類されています（🎓チュートリアル / 🔧ハウツー / 📖リファレンス / 💡解説）。

| Start here | Description |
|------------|-------------|
| [docs/tutorials/getting-started.md](docs/tutorials/getting-started.md) | 🎓 はじめてのセットアップ |
| [docs/explanation/architecture.md](docs/explanation/architecture.md) | 💡 設計思想・アーキテクチャ |
| [docs/reference/keybindings.md](docs/reference/keybindings.md) | 📖 キーバインド一覧 |

> 📖 全ドキュメントの一覧は [docs/README.md](docs/README.md) を参照してください。

---

## ✨ Customization / カスタマイズ

Fork して自分の環境に合わせてカスタマイズしてください。

```nix
# home.nix を編集
home.username = "your-username";
home.homeDirectory = "/home/your-username";
```

> 📖 詳細は [docs/how-to/customize-your-fork.md](docs/how-to/customize-your-fork.md) を参照してください。

---

## 🤝 Contributing

Contributions are welcome! / 改善や機能追加の提案は大歓迎です！

1. Fork this repository
2. Create feature branch
3. Make your changes
4. Test with `home-manager switch --flake .#archie`
5. Submit pull request

---

## 📜 License

MIT License

---

## 👤 Author

1saver (music-brain88)
