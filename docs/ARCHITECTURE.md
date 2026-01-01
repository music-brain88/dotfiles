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

1. **Reproducibility（再現性）**: どのマシンでも同じ環境を構築可能
2. **Flexibility（柔軟性）**: 既存の設定を活かしつつ、段階的に改善可能
3. **Separation of Concerns（関心の分離）**: パッケージ管理と設定管理を分離
4. **Tool Ecosystem Respect（ツールエコシステムの尊重）**: 各ツール固有の設定形式を活用

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
- [structure.md](./structure.md) - ディレクトリ構造
- [CLAUDE.md](../CLAUDE.md) - Claude Code向けコンテキスト

---

**この設計により、Nixの再現性と各ツールのネイティブ設定形式の柔軟性を両立しています。** 🎉
