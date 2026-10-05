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
├── tools/                   # 自作ツールのソース (Rust、flake の overlay でパッケージ化)
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

### In-repo Tools / 自作ツール

| ディレクトリ | 説明 |
|---|---|
| `tools/standalone-check/` | 配布文書の自立可読性チェッカー(Rust)。`standalone-report-writing` skill の点検手順から呼ぶ。`flake.nix` の overlay で `pkgs.standalone-check` として定義し、`nix/modules/dev-tools.nix` の `home.packages` で配る。単体ビルドは `nix build .#standalone-check`、開発は `cargo test`(Issue #639) |

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

`.config/` には、各アプリケーションの設定ファイルを格納している。

### Terminal & Shell

| Directory | Description |
|-----------|-------------|
| `bash/` | Bash 設定 (bashrc, bash_profile) - Fish へのブートストラップ用 |
| `fish/` | Fish shell 設定 (config.fish, functions/, conf.d/) |
| `tmux/` | Tmux 設定 (tmux.conf) |
| `wezterm/` | WezTerm ターミナル設定 (`wezterm.lua`、native Arch と Windows で共通)。native Arch のメインターミナル(Phase 3, #393) |
| `alacritty/` | Alacritty ターミナル設定 (併存期間中のフォールバック) |
| `starship/` | Starship プロンプト設定 |
| `herdr/` | herdr (agent multiplexer、tmux の後継) 設定 (`config.toml`) |

### Editor

| Directory | Description |
|-----------|-------------|
| `nvim/` | Neovim 設定 (TOML ベースのプラグイン管理) |

### Window Managers

| Directory | Description |
|-----------|-------------|
| `hypr/` | Hyprland 設定 (Wayland) |

### Notifications & Session

| Directory | Description |
|-----------|-------------|
| `mako/` | Mako 通知デーモン設定 (Wayland) |
| `systemd/` | systemd user units (`user/hyprland-session.target`) |

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

### AI Assistant Skills

スキルは、配線経路によって次の 2 層に分かれる。

- **tool-neutral 層**(`skills/`): エージェント横断の共有 SOP を置く(例: `learn`、`session-log`、`distill`)。`home.nix` で `.claude/skills/<name>` と `.copilot/skills/<name>` の両方へのマウントに解決され、単一ソースからドリフトしない(Issue #404)。
- **Claude 専用層**(`claude/skills/`): harness 固有の運用スキルを置く(例: `wt`、`wtclean`、`herdr`)。これらは `.claude` 全体の recursive マウント(`home.nix` の `".claude"` エントリ)でそのまま配布され、tool-neutral 層のような個別スキル単位の上書きマウントは持たない(個別の `.claude/skills/<name>` エントリが `home.nix` に存在するのは、あくまで tool-neutral 層の共有スキルを上書きするためである)。

新しいスキルを追加する際は、「特定 harness(Claude Code)の機能に依存するか」で配置を判断する。依存しなければ tool-neutral 層に置き、依存すれば Claude 専用層に置く。

次の表は、スキルとエージェント設定に関わるディレクトリを並べたものである。

| Directory | Description |
|-----------|-------------|
| `skills/` | ツール中立な共有スキル層。各サブディレクトリに `SKILL.md`(frontmatter は `name`/`description` のみ)。`home.nix` で `.claude/skills/<name>` と `.copilot/skills/<name>` の両方にマウントし、単一ソースからのドリフトを構造的に防ぐ(Issue #404)。スキルの一覧は `.config/skills/` 配下が正(列挙は追加のたびに腐るためここには書かない) |
| `claude/skills/` | Claude Code 専用スキル。`herdr`(環境固有)、`wt`/`wtclean`/`wtclose`(Claude の人格・herdr 前提。`wtclose` は Stop hook が呼ぶ検問スクリプト `close_gate.sh` とそのテストを同梱する)。旧 `claude/commands/` はスキル形式に統合済み(Claude Code はスキルをスラッシュコマンドとしても呼べる) |
| `copilot/` | GitHub Copilot CLI 設定。実体は `~/.copilot/`(`~/.config/copilot` ではない)。スキルは `skills/` からマウントされる共有分のみで、Copilot 固有のスキルディレクトリは持たない |

### Security

| Directory | Description |
|-----------|-------------|
| `gnupg/` | GPG agent 設定 (`gpg-agent.conf`、パスフレーズキャッシュTTL、pinentry-programの明示) |
| `pinentry/` | pinentry を curses/tty へ強制するフック (`preexec`、SSHセッションでのgnome3誤選択対策) |

### Media & Misc

| Directory | Description |
|-----------|-------------|
| `mpd/` | Music Player Daemon 設定 |
| `ncmpcpp/` | ncmpcpp (MPD クライアント) 設定 |
| `wakatime/` | WakaTime 設定 (config.sample のみ) |
| `fontconfig/` | フォント設定・トラブルシューティング |
| `mise/` | mise グローバル設定 (`config.toml`、リポジトリ横断のタスク・ツールバージョン管理) |
| `obsidian-web-clipper/` | Obsidian Web Clipper (ブラウザ拡張) のクリップテンプレート設定 |
| `ranger/` | ranger ファイラー設定 (`rc.conf`, `scope.sh`) |

---

## 📁 nix/modules/ - Nix Modules

Home Manager の設定は、`nix/modules/` の下でモジュールに分けている。

| Module | Description |
|--------|-------------|
| `base.nix` | 基本パッケージ (gnutar, protobuf, mako, libnotify, etc. — curl/wget/git/cmake は他モジュールへ移動済み) |
| `rust-tools.nix` | Rust 開発ツール (fd, ripgrep, eza, bat, etc.) |
| `shell.nix` | Fish shell + Starship 設定 |
| `git.nix` | Git 設定 (aliases, delta, gh) |
| `tmux.nix` | Tmux 設定とプラグイン (herdr 移行完了後に削除予定) |
| `herdr.nix` | herdr (agent multiplexer / tmux 後継) |
| `neovim.nix` | Neovim + LSP + formatters |
| `dev-tools.nix` | 開発ツール (Docker, AWS CLI, kubectl, etc.) |
| `fonts.nix` | フォント |
| `desktop.nix` | GUI 設定群 (hypr, waybar, wezterm, alacritty, wofi, mako, mpd, ncmpcpp, fontconfig) — native profile のみ |
| `wsl.nix` | WSL 固有: Obsidian vault symlink と Windows 側 WezTerm/Alacritty 設定の配布 — wsl profile のみ |

profile 分割の設計意図は [architecture.md の Per-Host Profiles](../explanation/architecture.md#-per-host-profiles) に書いてある。

---

## 📁 docs/ - Documentation (Diátaxis)

`docs/` の文書は、Diátaxis (https://diataxis.fr) に沿って4象限に分類している。詳細は [docs/README.md](../README.md) に書いてある。

| Directory | 象限 | Description |
|-----------|------|-------------|
| `tutorials/` | 🎓 Tutorial | 学習向け・ステップバイステップガイド |
| `how-to/` | 🔧 How-to | 作業向け・特定タスクの解決手順 |
| `reference/` | 📖 Reference | 逆引き向け・技術仕様の一覧 |
| `explanation/` | 💡 Explanation | 理解向け・設計や背景の解説 |

---

## 📁 llm/ - LLM Context Files

`llm/` には、AI アシスタント向けのコンテキストファイルを置いている。

| Directory/File | Description |
|----------------|-------------|
| `context/` | プロジェクト情報、技術スタック、ワークフロー |

---

## 📁 .github/ - GitHub Configuration

### Workflows

| File | Description |
|------|-------------|
| `workflows/nix.yml` | Nix CI/CD パイプライン |
| `workflows/build-docker-image.yml` | Docker イメージビルド (nix.yml から呼び出し) |
| `workflows/docs-lint.yml` | Markdown リンク切れチェック |
| `workflows/release-drafter.yml` | リリースノート自動生成 |
| `workflows/update-flake-lock.yml` | flake inputs の週次自動更新 (毎週月曜 03:00 UTC、更新 PR を自動作成) |

### Instructions & Templates

次の表は、GitHub Copilot 向けの指示ファイルと、Issue・PR のテンプレートを並べたものである。

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
