# Architecture / アーキテクチャ設計

このドキュメントでは、dotfilesリポジトリの設計思想とアーキテクチャについて説明します。

---

## 📚 Table of Contents

- [Design Philosophy](#design-philosophy)
- [Hybrid Approach](#hybrid-approach)
- [Module Structure](#module-structure)
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
├── tmux.nix        # Tmux関連
├── neovim.nix      # Neovim + LSP + formatters
└── dev-tools.nix   # 開発ツール（docker, kubectl, awscli）
```

### 分離の基準

1. **関連性**: 同じ目的のパッケージをグループ化
2. **依存関係**: 依存が少ないものを先に
3. **オプショナル**: 環境によって不要なものを分離可能に

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

---

## 🔄 CI/CD Architecture

### Hybrid Docker + Nix Pipeline

```
┌─────────────────┐
│  GitHub Actions │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  Docker Image (ghcr.io/.../env)     │
│  ├── Nix pre-installed              │
│  ├── Base packages cached           │
│  └── Development tools              │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│  Nix Build                          │
│  ├── nix flake check                │
│  ├── nix build .#homeConfigurations │
│  └── magic-nix-cache (store cache)  │
└─────────────────────────────────────┘
```

### Why Docker?

**Dockerを採用している主な理由：複数環境でのテストを視野に入れている**

| Target | Status | Purpose |
|--------|--------|---------|
| Arch Linux | ✅ Primary | メイン開発環境 |
| Ubuntu | 🔜 Planned | サーバー環境、WSL |
| Other distros | 🔜 Planned | 汎用性の確認 |

**Dockerにより：**
- 異なるディストリビューションでの動作確認が可能
- Nix環境のベースイメージを共有できる
- GitHub Actionsのキャッシュ機能と組み合わせて高速化

### Caching Strategy

| Layer | Caching | Purpose |
|-------|---------|---------|
| Docker | Layer cache | Nix installation, base setup |
| Nix | magic-nix-cache | Package builds, derivations |

**Benefits:**
- Nix再インストール不要（Docker層でキャッシュ）
- パッケージビルドもキャッシュ（Nixキャッシュ）
- ディスク容量の心配なし

### Overlays for CI

```nix
# flake.nix
overlays = [
  (final: prev: {
    # CIでテストが失敗するパッケージを修正
    rustup = prev.rustup.overrideAttrs (old: {
      doCheck = false;  # ネットワークテストを無効化
    });
  })
];
```

CI環境特有の問題（サンドボックス、ネットワーク制限）を回避。

---

## 📊 Decision Matrix

新しいツールを追加する際の判断基準：

| Question | Yes → | No → |
|----------|-------|------|
| 設定ファイルが複雑？ | Symlink | Package Only |
| 既存の設定がある？ | Symlink | programs.* or Package Only |
| ツール固有のDSL/形式？ | Symlink（ネイティブ形式を活用） | - |
| 設定不要なCLI？ | Package Only | - |

---

## 🔗 Related Documentation

- [NIX.md](./NIX.md) - Nix/Home Manager 使い方ガイド
- [STRUCTURE.md](./STRUCTURE.md) - ディレクトリ構造
- [WORKFLOW.md](./WORKFLOW.md) - 作業ワークフロー
- [CLAUDE.md](../CLAUDE.md) - Claude Code向けコンテキスト

---

**この設計により、Nixの再現性と各ツールのネイティブ設定形式の柔軟性を両立しています。** 🎉
