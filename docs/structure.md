# Directory Structure / ディレクトリ構造

このドキュメントでは、dotfilesリポジトリのディレクトリ構造と各コンポーネントの役割を説明します。

---

## 📁 Overview

```
dotfiles/
├── .config/                 # アプリケーション設定ファイル
├── .github/                 # GitHub Actions ワークフロー
├── docs/                    # ドキュメント
├── llm/                     # LLM コンテキストファイル
├── nix/                     # Nix モジュール
├── polybar-themes/          # Polybar テーマ (submodule)
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
| `fish/` | Fish shell 設定 (config.fish, functions/, conf.d/) |
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
| `i3/` | i3 設定 (X11) |

### Status Bars

| Directory | Description |
|-----------|-------------|
| `waybar/` | Waybar 設定 (Wayland) |
| `polybar/` | Polybar 設定 (X11) |

### Launchers

| Directory | Description |
|-----------|-------------|
| `rofi/` | Rofi ランチャー設定 (X11) |
| `wofi/` | Wofi ランチャー設定 (Wayland) |

### Media & Misc

| Directory | Description |
|-----------|-------------|
| `mpd/` | Music Player Daemon 設定 |
| `ncmpcpp/` | ncmpcpp (MPD クライアント) 設定 |
| `picom/` | Picom コンポジター設定 (X11) |

---

## 📁 nix/modules/ - Nix Modules

Home Manager の設定をモジュール化。

| Module | Description |
|--------|-------------|
| `base.nix` | 基本パッケージ (curl, wget, git, cmake, etc.) |
| `rust-tools.nix` | Rust 開発ツール (fd, ripgrep, eza, bat, etc.) |
| `shell.nix` | Fish shell + Starship 設定 |
| `git.nix` | Git 設定 (aliases, delta, gh) |
| `tmux.nix` | Tmux 設定とプラグイン |
| `neovim.nix` | Neovim + LSP + formatters |
| `dev-tools.nix` | 開発ツール (Docker, AWS CLI, kubectl, etc.) |

---

## 📁 docs/ - Documentation

| File | Description |
|------|-------------|
| `NIX.md` | Nix/Home Manager 詳細ガイド |
| `structure.md` | このファイル（ディレクトリ構造） |

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

### Templates

| Directory | Description |
|-----------|-------------|
| `ISSUE_TEMPLATE/` | Issue テンプレート |
| `PULL_REQUEST_TEMPLATE.md` | PR テンプレート |

---

## 📁 polybar-themes/

Polybar テーマ集（Git submodule）。

```bash
# サブモジュールを初期化
git submodule init
git submodule update
```

---

## 🔗 Related Documentation

- [README.md](../README.md) - プロジェクト概要とクイックスタート
- [NIX.md](./NIX.md) - Nix/Home Manager 詳細ガイド
- [CLAUDE.md](../CLAUDE.md) - Claude Code 向けコンテキスト
