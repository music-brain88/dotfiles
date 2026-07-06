# Directory Structure / ディレクトリ構造

> **Diátaxis:** 📖 Reference

このドキュメントでは、dotfilesリポジトリのディレクトリ構造と各コンポーネントの役割を説明します。

---

## 📁 Overview

```
dotfiles/
├── .config/                 # アプリケーション設定ファイル
├── .github/                 # GitHub Actions ワークフロー
├── docs/                    # ドキュメント (Diátaxis構成)
│   ├── tutorials/           # 学習向け
│   ├── how-to/              # 作業向け
│   ├── reference/           # 逆引き向け
│   └── explanation/         # 理解向け
├── llm/                     # LLM コンテキストファイル
├── nix/                     # Nix モジュール
├── .mise.toml               # タスクランナー設定
├── flake.nix                # Nix Flake エントリーポイント
├── home.nix                 # Home Manager メイン設定
├── Dockerfile               # Docker 環境構築用
└── README.md                # プロジェクト概要
```

---

## 📄 Root Files / ルートファイル

### Nix Configuration

| File | Description |
|------|-------------|
| `flake.nix` | Nix Flake のエントリーポイント。依存関係と出力を定義 |
| `flake.lock` | 依存関係のバージョンをロック |
| `home.nix` | Home Manager のメイン設定ファイル |

### Task Runner

| File | Description |
|------|-------------|
| `.mise.toml` | mise タスク定義とツールバージョン管理 |

### Docker

| File | Description |
|------|-------------|
| `Dockerfile` | CI/CD および開発用 Docker イメージ |

---

## 📁 .config/ - Application Configurations

各アプリケーションの設定ファイルを格納。

### Terminal & Shell

| Directory | Description |
|-----------|-------------|
| `bash/` | Bash 設定 (bashrc, bash_profile) - Fish へのブートストラップ用 |
| `fish/` | Fish shell 設定 (config.fish, functions/, conf.d/) |
| `tmux/` | Tmux 設定 (tmux.conf) |
| `alacritty/` | Alacritty ターミナル設定 |
| `starship/` | Starship プロンプト設定 |

### Editor

| Directory | Description |
|-----------|-------------|
| `nvim/` | Neovim 設定 (TOML ベースのプラグイン管理) |

### Window Managers

| Directory | Description |
|-----------|-------------|
| `hypr/` | Hyprland 設定 (Wayland) |

### Status Bars

| Directory | Description |
|-----------|-------------|
| `waybar/` | Waybar 設定 (Wayland) |

### Launchers

| Directory | Description |
|-----------|-------------|
| `wofi/` | Wofi ランチャー設定 (Wayland) |

### Version Control

| Directory | Description |
|-----------|-------------|
| `git/` | Git 設定 (config, ignore, config.local.sample) |

### Media & Misc

| Directory | Description |
|-----------|-------------|
| `mpd/` | Music Player Daemon 設定 |
| `ncmpcpp/` | ncmpcpp (MPD クライアント) 設定 |
| `wakatime/` | WakaTime 設定 (config.sample のみ) |
| `fontconfig/` | フォント設定・トラブルシューティング |

---

## 📁 nix/modules/ - Nix Modules

Home Manager の設定をモジュール化。

| Module | Description |
|--------|-------------|
| `base.nix` | 基本パッケージ (curl, wget, git, cmake, etc.) |
| `rust-tools.nix` | Rust 開発ツール (fd, ripgrep, eza, bat, etc.) |
| `shell.nix` | Fish shell + Starship 設定 |
| `git.nix` | Git 設定 (aliases, delta, gh) |
| `tmux.nix` | Tmux 設定とプラグイン (herdr 移行完了後に削除予定) |
| `herdr.nix` | herdr (agent multiplexer / tmux 後継) |
| `neovim.nix` | Neovim + LSP + formatters |
| `dev-tools.nix` | 開発ツール (Docker, AWS CLI, kubectl, etc.) |
| `fonts.nix` | フォント |
| `desktop.nix` | GUI 設定群 (hypr, waybar, alacritty, wofi, mako, mpd, ncmpcpp, fontconfig) — native profile のみ |
| `wsl.nix` | WSL 固有: Obsidian vault symlink と Windows 側 Alacritty 設定の配布 — wsl profile のみ |

profile 分割の設計意図は [architecture.md の Per-Host Profiles](../explanation/architecture.md#per-host-profiles) を参照。

---

## 📁 docs/ - Documentation (Diátaxis)

Diátaxis (https://diataxis.fr) に沿って4象限に分類。詳細は [docs/README.md](../README.md) を参照。

| Directory | 象限 | Description |
|-----------|------|-------------|
| `tutorials/` | 🎓 Tutorial | 学習向け・ステップバイステップガイド |
| `how-to/` | 🔧 How-to | 作業向け・特定タスクの解決手順 |
| `reference/` | 📖 Reference | 逆引き向け・技術仕様の一覧 |
| `explanation/` | 💡 Explanation | 理解向け・設計や背景の解説 |

---

## 📁 llm/ - LLM Context Files

AI アシスタント向けのコンテキストファイル。

| Directory/File | Description |
|----------------|-------------|
| `context/` | プロジェクト情報、技術スタック、ワークフロー |
| `personalities/` | AI ペルソナ設定 |

---

## 📁 .github/ - GitHub Configuration

### Workflows

| File | Description |
|------|-------------|
| `workflows/nix.yml` | Nix CI/CD パイプライン |
| `workflows/build-docker-image.yml` | Docker イメージビルド (nix.yml から呼び出し) |
| `workflows/docs-lint.yml` | Markdown リンク切れチェック |
| `workflows/release-drafter.yml` | リリースノート自動生成 |

### Instructions & Templates

| Directory/File | Description |
|-----------------|-------------|
| `copilot-instructions.md` | GitHub Copilot 向けコンテキスト |
| `ISSUE_TEMPLATE/` | Issue テンプレート |
| `PULL_REQUEST_TEMPLATE.md` | PR テンプレート |

---

## 🔗 Related Documentation

- [README.md](../../README.md) - プロジェクト概要とクイックスタート
- [architecture.md](../explanation/architecture.md) - アーキテクチャ設計・設計思想
- [getting-started.md](../tutorials/getting-started.md) - Nix/Home Manager 詳細ガイド
- [keybindings.md](./keybindings.md) - キーバインド・ショートカット一覧
- [neovim-config.md](./neovim-config.md) - Neovim 設定ガイド
- [CLAUDE.md](../../CLAUDE.md) - Claude Code 向けコンテキスト
