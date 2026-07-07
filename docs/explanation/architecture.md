# Architecture / アーキテクチャ設計

> **Diátaxis:** 💡 Explanation

このドキュメントでは、dotfilesリポジトリの設計思想とアーキテクチャについて説明します。

---

## 📚 Table of Contents

- [Design Philosophy](#design-philosophy)
- [Hybrid Approach](#hybrid-approach)
- [Module Structure](#module-structure)
- [Per-Host Profiles](#per-host-profiles)
- [Configuration Strategies](#configuration-strategies)
- [CI/CD Architecture](#cicd-architecture)

---

## 🎯 Design Philosophy

### Core Principles

1. **Simplicity（シンプルさ）**: Arch Linuxの哲学に倣い、設定や構成を可能な限りシンプルに保つ。不要な複雑さを避け、必要最小限の設定で最大限の効果を得る
2. **Reproducibility（再現性）**: どのマシンでも同じ環境を構築可能。GitHub ActionsやDockerを活用し、環境構築を自動化・標準化する
3. **Efficiency（効率性）**: 頻繁に行う操作や繰り返し作業を自動化し、作業効率を最大化。Fishシェルやskim、Neovimのプラグインを活用
4. **Extensibility（拡張性）**: 将来的な変更や新しいツールの導入に柔軟に対応。モジュール化された設定ファイルやプラグイン管理を通じて、容易に拡張可能な構成を維持
5. **Maintainability（メンテナンス性）**: 設定ファイルやスクリプトを整理し、メンテナンスやアップデートが容易になるように。ドキュメントを整備し、設定の意図や使い方を明確にする
6. **Elegance（美しさ）**: Rust言語のように、設定やコードの美しさや読みやすさを重視。一貫したスタイルやフォーマットを維持
7. **Declarative Management（宣言的管理）**: 「どのように（How）」ではなく「何を（What）」を明確に記述し、設定の意図を明確にしてメンテナンス性を向上させる

### Practical Implementation

上記の設計思想を実現するための具体的な取り組み：

- **設定ファイルのモジュール化**: 用途やツールごとに細かく分割。NeovimはプラグインごとにTOMLファイルに分割してdein.vimで管理
- **シンボリックリンクの活用**: dotfilesリポジトリ内の設定ファイルをホームディレクトリにシンボリックリンクし、一元管理を実現
- **CI/CDによる自動化**: GitHub Actionsを活用して設定ファイルや開発環境の構築を自動化
- **ドキュメントの整備**: 設定ファイルやスクリプトの意図や使い方を明確にするためにドキュメントを整備
- **Rust製ツールの活用**: ripgrep, fd, bat, gituiなどRust製CLIツールを積極的に活用し、作業効率を向上

### Why Nix?（従来のシェルスクリプトとの比較）

従来のシェルスクリプトベースのセットアップには以下の問題がありました:

1. **重複コード**: 同じツールのインストールが複数箇所に存在
2. **再現性の欠如**: 依存関係のバージョンが環境によって異なる
3. **複雑な状態管理**: 複数のスクリプトにまたがる状態管理
4. **ロールバック不可**: 問題が発生した場合、元に戻すのが困難
5. **CI/CDの複雑化**: 9つの別々のワークフローファイルを管理

Nixを使用することで、以下のメリットが得られます:

✅ **再現可能**: どのマシンでも同じ環境を構築可能
✅ **宣言的**: 設定ファイルで環境全体を定義
✅ **アトミック**: アップグレードやロールバックが安全に実行可能
✅ **依存関係の自動管理**: 必要なパッケージを自動的に解決
✅ **バージョン固定**: 特定のバージョンを固定して使用可能
✅ **分離された環境**: 複数のバージョンを共存させることが可能

### Why Nix + Symlinks?

従来のdotfiles管理には2つのアプローチがあります：

| Approach | Pros | Cons |
|----------|------|------|
| **Pure Nix** | 完全な再現性、宣言的 | 既存設定の移行が大変、学習コスト高 |
| **Pure Symlinks** | シンプル、柔軟 | パッケージ管理が別途必要、環境差異 |

**このリポジトリでは「ハイブリッドアプローチ」を採用：**

```
Nix/Home Manager
├── パッケージのインストール（再現性）
├── パッケージのバージョン固定（再現性）
└── シンボリックリンクの作成
    ↓
既存の設定ファイル（柔軟性）
├── .config/nvim/*.toml
├── .config/fish/config.fish
├── .config/hypr/keybinds.conf
└── ...
```

---

## 🔀 Hybrid Approach

### Nixの役割

```nix
# パッケージのインストールのみ
home.packages = with pkgs; [
  fish
  starship
  # ...
];

# 設定ファイルはシンボリックリンク
home.file.".config/fish/config.fish".source = ../../.config/fish/config.fish;
```

**Nixが担当するもの：**
- パッケージのインストール
- 依存関係の解決
- バージョンの固定（flake.lock）
- シンボリックリンクの作成

**Nixが担当しないもの：**
- 設定ファイルの中身
- プラグインの設定（Neovimのdein.vim等）

### 言語ランタイムのバージョン方針 / Language Runtime Version Policy

Python / Node などの言語ランタイムは、NixとmiseのW管理にならないよう役割を分担する：

| 担当 | 役割 | 例 |
|------|------|-----|
| **Nix** | ベースライン提供（バージョン指名しない） | `python3`, `nodejs`（`nix/modules/dev-tools.nix`） |
| **mise** | プロジェクトごとのバージョン固定 | 各リポジトリの `.mise.toml`（例: `node = "22.15.1"`） |

- Nix側でバージョンを指名しない理由: デフォルト版はHydraのバイナリキャッシュに乗るが、指名するとソースビルドに落ちやすい（`nix/modules/neovim.nix` のpython3コメント参照）
- miseの `globalConfig` にツールを書かない理由: source of truth を各プロジェクトの `.mise.toml` に一本化するため

Nix provides unpinned baseline runtimes (binary-cache friendly); mise pins versions per project via each repo's `.mise.toml`. No global mise tools, so there is exactly one source of truth per project.

### なぜこのアプローチ？

#### 1. ツールごとに設定形式が異なる

すべてのツールが同じ設定形式になることはありえない。各ツールは独自のエコシステムを持っている：

| Tool | Native Config Format | Why Keep Native |
|------|---------------------|-----------------|
| Neovim (dein.vim) | TOML | dein.vimはTOML前提の設計 |
| Fish | `.fish` | 補完・関数が独自形式 |
| Starship | TOML | 公式がTOML推奨 |
| Hyprland | Custom DSL | Hypr独自のシンタックス |
| Alacritty | TOML/YAML | 公式ドキュメントがTOML/YAML |
| Tmux | tmux.conf | 独自のコマンド形式 |

**Nix式に統一するメリットがない。むしろ各ツールのネイティブ形式を使う方が：**
- 公式ドキュメントがそのまま使える
- ツール固有の機能（シンタックスハイライト、LSP等）が活用できる
- 設定の共有・参考にしやすい

#### 2. 既存の設定を活かす

Neovimの設定は13個のTOMLファイルで構成されています：

```
.config/nvim/
├── dein.toml           # 200+ lines
├── ddc_settings.toml   # 160+ lines
├── ddu_settings.toml   # 400+ lines
├── lsp_settings.toml   # 120+ lines
└── ...
```

これらをNix式に書き直すのは：
- 膨大な作業量
- 既存の動作確認済み設定を捨てることになる
- dein.vimのエコシステムから離れる

#### 3. Nixの強みに集中

Nixは**パッケージ管理**と**環境の再現性**に特化させる。設定ファイルの管理は各ツールのネイティブ形式に任せる。

---

## 📦 Module Structure

### Nixモジュールの分離

```
nix/modules/
├── base.nix        # 基本パッケージ（curl, wget, git, cmake）
├── rust-tools.nix  # Rustツールチェーン（fd, ripgrep, eza, bat）
├── shell.nix       # シェル関連（fish, starship, plugins）
├── git.nix         # Git関連（git, delta, gh, copilot-cli）
├── tmux.nix        # Tmux関連（herdr 移行完了後に削除予定）
├── herdr.nix       # herdr（agent multiplexer / tmux 後継）
├── neovim.nix      # Neovim + LSP + formatters
├── dev-tools.nix   # 開発ツール（docker, kubectl, awscli）
├── fonts.nix       # フォント
├── desktop.nix     # GUI 設定群（hypr, waybar, alacritty 等）— native profile のみ
└── wsl.nix         # WSL 固有（Obsidian vault symlink, Alacritty 配布）— wsl profile のみ
```

### 分離の基準

1. **関連性**: 同じ目的のパッケージをグループ化
2. **依存関係**: 依存が少ないものを先に
3. **オプショナル**: 環境によって不要なものを分離可能に

---

## 🖥 Per-Host Profiles

### 2マシンとアイデンティティ境界

この dotfiles は2台のマシン（ネイティブ Arch Linux = 個人機、Windows 11 + WSL2 = 仕事機）で運用される。
2つの世界をまたぐ**共有スパイン**と、マシンごとに**分離するアカウント**を明示的に区別する:

| | 個人機 (Arch native) | 仕事機 (Windows + WSL2) |
|---|---|---|
| **共有スパイン** | GitHub（dotfiles = コード環境の再現性）/ Obsidian（vault = 知識の一元化、Obsidian Sync 同期） | 同左 |
| **分離するもの** | 個人の Claude / ClickUp / Google | 仕事の Claude / ClickUp / Google |

### 所有権境界: 「PTY は WSL、ピクセルは WSLg」

当初は「ピクセルは host」方針で terminal emulator（Alacritty）を Windows ネイティブアプリの
まま使っていたが、Windows 版 Alacritty は ConPTY 経由の画面更新を取りこぼす未解決バグがあり
（[alacritty/alacritty#8057](https://github.com/alacritty/alacritty/issues/8057)）、
herdr の画面切り替えで前画面の文字が残る描画破損が発生した。同じ ConPTY を通す
Windows Terminal では再現しないため、Alacritty 側の読み取り処理が原因。

このため WSL では **WSLg 経由の Linux 版 Alacritty を主とし、ConPTY を経路から排除する**。
PTY・emulator・設定がすべて Linux 側に揃い、native Arch と同じ管理形態になる利点もある
（パッケージは pacman、設定は Nix symlink。nixpkgs の Alacritty は EGL が WSLg の
GL スタックと噛み合わず起動しないため、GUI アプリは distro 管理という native の流儀を踏襲）。
トレードオフは GUI 統合（日本語 IME・HiDPI）が WSLg 品質に依存すること。
Windows 版 Alacritty はフォールバックとして残し、`alacritty.toml` は従来どおり
`nix:switch` 時に `%APPDATA%` へ配布する（`nix/modules/wsl.nix`）。

### profile の構造

`flake.nix` の `homeConfigurations` は 2 profile を持ち、`mise run nix:switch` がカーネル名から自動判別する:

- **`archie`**（native）: 共通モジュール + `desktop.nix`（GUI 設定群）
- **`archie-wsl`**（wsl）: 共通モジュール + `wsl.nix`
  - `~/Documents/Obsidian` → Windows 側 vault への symlink を activation で生成（Claude Cowork / Obsidian Sync が vault の実体を Windows 側に要請するため）。これによりスキル群（session-log 等）はパス変更なしで両環境動作する
  - **vault 配置規約**: Obsidian Sync が同期するのは vault の中身と名前だけで、ローカルの置き場所は各端末で選ぶもの。この dotfiles では「Windows ホストでは `%USERPROFILE%\Documents\music.brain88` に配置する」を運用規約とし、`wsl.nix` はその規約をコード化している（見つからない場合は警告して skip、activation は落ちない）
  - Linux 版 Alacritty（WSLg 経由、パッケージは pacman）を主ターミナルとし、設定を symlink（ConPTY バグ回避、上記「所有権境界」参照）
    - Windows 側からの起動: `"C:\Program Files\WSL\wslg.exe" --cd ~ -- env -u WAYLAND_DISPLAY alacritty`（Store 版 WSL の wslg.exe は System32 ではなく Program Files 配下。コンソールウィンドウなしで起動できる）
    - **X11 (Xwayland) 経由が必須**: winit アプリが Wayland ネイティブで接続すると、ウィンドウのリサイズ・ドラッグで WSLg の Weston が libpixman 内で segfault し全ウィンドウが道連れになる（[microsoft/wslg#1386](https://github.com/microsoft/wslg/issues/1386)、未解決）。`env -u WAYLAND_DISPLAY` で Xwayland 経由に迂回すると安定する（実測で確認済み）
  - フォールバック用に Windows 側 Alacritty 設定も base + `windows.toml` 差分のマージで生成し `%APPDATA%` へ配布（Windows でも fish + herdr が自動起動）

---

## ⚙️ Configuration Strategies

### Strategy 1: Package Only + Symlink

**使用場面**: 設定が複雑で、既存の設定ファイルを活かしたい場合

```nix
# shell.nix
home.packages = with pkgs; [
  fish
  starship
];

# 設定はシンボリックリンク
home.file.".config/fish/config.fish".source = ../../.config/fish/config.fish;
xdg.configFile."starship.toml".source = ../../.config/starship/starship.toml;
```

**採用例**: Fish, Neovim, Hyprland, Alacritty, Tmux

### Strategy 2: programs.* with Native Config

**使用場面**: Nixが提供する設定オプションを活用しつつ、設定ファイルは別管理

```nix
# neovim.nix
programs.neovim = {
  enable = true;
  defaultEditor = true;
  viAlias = true;
  vimAlias = true;
  extraPackages = with pkgs; [
    lua-language-server
    rust-analyzer
    # ...
  ];
};
```

**ポイント**: `programs.neovim.enable`を使いつつ、設定ファイル自体は`home.file`でシンボリックリンク

**採用例**: Neovim（パッケージはprograms.*、設定はsymlink）

### Strategy 3: Package Only (No Config)

**使用場面**: 設定不要なCLIツール

```nix
# rust-tools.nix
home.packages = with pkgs; [
  fd
  ripgrep
  eza
  bat
];
```

**採用例**: 大半のCLIツール

### Strategy 4: Initial Seed (Runtime Writable)

**使用場面**: ツールが動的にファイルを読み書きするため、Nixのシンボリックリンク（読み取り専用）では管理できない場合

```nix
# home.nix
home.activation.seedCopilotConfig = config.lib.dag.entryAfter [ "writeBoundary" ] ''
  target="$HOME/.config/.copilot/config.json"
  if [ ! -f "$target" ] || [ -L "$target" ]; then
    mkdir -p "$(dirname "$target")"
    rm -f "$target"
    cp ${./.config/copilot/config.json} "$target"
    chmod 644 "$target"
  fi
'';
```

**動作**:
- ファイルが**存在しない**（新環境） → dotfilesからコピーしてシード
- ファイルが**シンボリックリンク**（旧状態から移行） → 削除して新しくコピー
- ファイルが**普通のファイル**（既に使用中） → 何もしない（ツールの変更を尊重）

**リセット**: `rm <target>` して `nix:switch` すれば dotfiles の内容で再シードされる

**採用例**: GitHub Copilot CLI (`config.json`) — CLIがtrusted foldersやモデル設定を書き込む

---

## 🔄 CI/CD Architecture

> 詳細は [cicd-evolution.md](./cicd-evolution.md)（Evolution History、Lessons Learned 等）と [ci-cd-pipeline.md](../reference/ci-cd-pipeline.md)（現在の構成）を参照

### Hybrid Docker + Nix Pipeline

GitHub Actionsのディスク容量制限（約14GB）を回避するため、Nixがプリインストールされた Docker コンテナを使用。

```
┌─────────────────────────────────────────────────────┐
│  GitHub Actions (nix.yml)                           │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌─────────────┐     ┌─────────────┐               │
│  │ build-image │     │    check    │               │
│  │             │     │             │               │
│  │ Docker image│     │ flake check │  ← 並列実行   │
│  │ build/push  │     │ format check│               │
│  └──────┬──────┘     └──────┬──────┘               │
│         │                   │                       │
│         └─────────┬─────────┘                       │
│                   ▼                                 │
│         ┌─────────────────┐                        │
│         │  verify-docker  │                        │
│         │                 │                        │
│         │ Build & activate│                        │
│         │ in Arch Linux   │                        │
│         │ container       │                        │
│         └─────────────────┘                        │
└─────────────────────────────────────────────────────┘
```

### Pipeline Stages

| Stage | Purpose |
|-------|---------|
| **build-image** | Docker イメージをビルドしてGHCRにプッシュ |
| **check** | `nix flake check --no-build`、フォーマット検証 |
| **verify-docker** | Arch Linux コンテナ内でビルド＆アクティベーション |

### Caching Strategy

| Layer | Tool | Purpose |
|-------|------|---------|
| Docker | `type=gha` layer cache | Nix installation, base setup |
| Nix (check) | `magic-nix-cache` | 軽量チェック用 |
| Nix (verify) | `cache-nix-action` | Docker内ビルド用 |

**Note**: `magic-nix-cache` はDockerコンテナ内では動作しない（Nix daemonイベント購読方式のため）。
詳細は [cicd-evolution.md - Phase 3](./cicd-evolution.md#phase-3-magic-nix-cache-の限界-216) を参照。

---

## 📊 Decision Matrix

新しいツールを追加する際の判断基準：

| Question | Yes → | No → |
|----------|-------|------|
| 設定ファイルが複雑？ | Symlink | Package Only |
| 既存の設定がある？ | Symlink | programs.* or Package Only |
| ツール固有のDSL/形式？ | Symlink（ネイティブ形式を活用） | - |
| ツールが設定を動的に書き換える？ | Initial Seed（activation script） | Symlink |
| 設定不要なCLI？ | Package Only | - |

---

## 🔗 Related Documentation

- [cicd-evolution.md](./cicd-evolution.md) - CI/CDの課題・変遷・教訓
- [ci-cd-pipeline.md](../reference/ci-cd-pipeline.md) - CI/CDパイプライン詳細
- [install-and-update-packages.md](../how-to/install-and-update-packages.md) - Nix/Home Manager 使い方ガイド
- [directory-structure.md](../reference/directory-structure.md) - ディレクトリ構造
- [daily-workflow-commands.md](../how-to/daily-workflow-commands.md) - 作業ワークフロー
- [CLAUDE.md](../../CLAUDE.md) - Claude Code向けコンテキスト

---

**この設計により、Nixの再現性と各ツールのネイティブ設定形式の柔軟性を両立しています。** 🎉
