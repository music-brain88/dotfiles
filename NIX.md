# Nix/Home Manager Guide

このドキュメントでは、dotfilesリポジトリにおけるNix/Home Managerの使い方を説明します。

## 📚 Table of Contents

- [Overview](#overview)
- [Why Nix?](#why-nix)
- [Installation](#installation)
- [Usage](#usage)
- [Module Structure](#module-structure)
- [Customization](#customization)
- [Troubleshooting](#troubleshooting)
- [Migration from Shell Scripts](#migration-from-shell-scripts)

---

## 🎯 Overview

このdotfilesリポジトリは、Nix FlakesとHome Managerを使用して、宣言的で再現可能な開発環境を提供します。

### Architecture

```
flake.nix                 # Nix Flakeのエントリーポイント
│
├── home.nix              # Home Managerのメイン設定
│
└── nix/modules/          # モジュール化された設定
    ├── base.nix          # 基本パッケージ
    ├── rust-tools.nix    # Rust開発ツール
    ├── shell.nix         # Fish shell + Starship
    ├── git.nix           # Git設定
    ├── tmux.nix          # Tmux設定
    ├── neovim.nix        # Neovim設定
    └── dev-tools.nix     # 開発ツール
```

---

## 🚀 Why Nix?

### Problems with Traditional Shell Scripts

従来のシェルスクリプトベースのセットアップには以下の問題がありました:

1. **重複コード**: 同じツールのインストールが複数箇所に存在
2. **再現性の欠如**: 依存関係のバージョンが環境によって異なる
3. **複雑な状態管理**: 複数のスクリプトにまたがる状態管理
4. **ロールバック不可**: 問題が発生した場合、元に戻すのが困難
5. **CI/CDの複雑化**: 9つの別々のワークフローファイルを管理

### Benefits of Nix/Home Manager

Nixを使用することで、以下のメリットが得られます:

✅ **再現可能**: どのマシンでも同じ環境を構築可能
✅ **宣言的**: 設定ファイルで環境全体を定義
✅ **アトミック**: アップグレードやロールバックが安全に実行可能
✅ **依存関係の自動管理**: 必要なパッケージを自動的に解決
✅ **バージョン固定**: 特定のバージョンを固定して使用可能
✅ **分離された環境**: 複数のバージョンを共存させることが可能

---

## 📦 Installation

### 1. Install Nix

**Option A: Official Nix Installer**

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

> ⚠️ **重要**: 公式インストーラーを使った場合、Flakesを手動で有効化する必要があります:
>
> ```bash
> mkdir -p ~/.config/nix
> echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
> ```

**Option B: Determinate Systems Installer (推奨)**

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Determinate Systems installerは以下の機能を提供します:
- Flakesとnix-commandが自動的に有効化
- より良いデフォルト設定
- アンインストールが簡単

### 2. Verify Installation

```bash
nix --version
```

### 3. Clone Repository

```bash
git clone https://github.com/archie/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

### 4. Build and Activate

```bash
# Recommended: Use home-manager directly
home-manager switch --flake .#archie

# If home-manager is not installed yet
nix run home-manager/master -- switch --flake .#archie

# Alternative: Manual build and activate
nix build .#homeConfigurations.archie.activationPackage
./result/activate
```

#### Flake URL の構文について

`#` はシェルのコメントではなく、Nix flake の出力を指定するための区切り文字です：

```
.#archie
↑ ↑
│ └── flake の出力名（homeConfigurations.archie）
└── flake のパス（現在のディレクトリ）
```

他の例：
```bash
# ローカルの flake から archie の設定を使う
home-manager switch --flake .#archie

# GitHub から直接使う場合
home-manager switch --flake github:user/dotfiles#archie

# パスを指定する場合
home-manager switch --flake /path/to/dotfiles#archie
```

### 5. Install Neovim Plugins

```bash
nvim --headless +"call dein#install()" +qall
```

---

## 🛠️ Usage

### Updating Packages

```bash
# Update all flake inputs (nixpkgs, home-manager, etc.)
nix flake update

# Rebuild and activate the updated configuration
nix run home-manager/master -- switch --flake .#archie
```

### Updating Specific Package

```bash
# Update only nixpkgs
nix flake lock --update-input nixpkgs

# Rebuild
nix run home-manager/master -- switch --flake .#archie
```

### Rolling Back

```bash
# List all generations
home-manager generations

# Rollback to previous generation
/nix/store/<hash>-home-manager-generation/activate

# Or use the generation number
home-manager generations | head -2 | tail -1 | awk '{print $7}' | xargs -I {} {}/activate
```

### Garbage Collection

```bash
# Remove old generations
nix-collect-garbage -d

# Or keep last N days
nix-collect-garbage --delete-older-than 30d
```

### Development Shell

```bash
# Enter development shell with Nix tools
nix develop

# Available tools: nil, nixpkgs-fmt, nix-tree
```

---

## 📂 Module Structure

### base.nix

基本的なシステムパッケージを定義:
- curl, wget, git
- cmake, pkg-config
- mako, libnotify

### rust-tools.nix

Rust開発ツールとCLIツールを定義:
- rustup, cargo
- fd, ripgrep, eza, bat
- gitui, tealdeer, hyperfine

### shell.nix

Fish shellとStarshipの設定:
- Fish shell with plugins (z, bass)
- Starship prompt configuration
- Shell aliases and functions

### git.nix

Git設定:
- User information
- Aliases
- Delta (better diff viewer)
- GitHub CLI (gh)

### tmux.nix

Tmux設定:
- Key bindings
- Status bar configuration
- Plugins (sensible, yank, resurrect, etc.)

### neovim.nix

Neovim設定:
- Language servers (LSP)
- Formatters and linters
- Tree-sitter
- Python environment for Neovim

### dev-tools.nix

開発ツール:
- Container tools (Docker, lazydocker)
- Cloud tools (AWS CLI, kubectl, k9s)
- Database clients
- Language runtimes
- System monitoring tools

---

## ✨ Customization

### Adding New Packages

`home.nix` または対応するモジュールファイルに追加:

```nix
# nix/modules/dev-tools.nix
home.packages = with pkgs; [
  # Existing packages...

  # Add new package
  neofetch
  htop
];
```

### Changing User Information

`home.nix` を編集:

```nix
home.username = "your-username";
home.homeDirectory = "/home/your-username";
```

`nix/modules/git.nix` を編集:

```nix
programs.git = {
  userName = "Your Name";
  userEmail = "your.email@example.com";
};
```

### Creating New Module

1. `nix/modules/` に新しいモジュールファイルを作成:

```nix
# nix/modules/custom.nix
{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Your packages here
  ];

  # Additional configuration
}
```

2. `home.nix` でモジュールをインポート:

```nix
imports = [
  # Existing modules...
  ./nix/modules/custom.nix
];
```

### Overriding Package Versions

特定のパッケージのバージョンを固定する場合:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";  # Specific version
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, ... }: {
    # Use unstable for specific packages
    homeConfigurations.archie = {
      home.packages = [
        nixpkgs-unstable.legacyPackages.${system}.neovim
      ];
    };
  };
}
```

---

## 🐛 Troubleshooting

### Common Issues

#### 1. Flakes not enabled

**Error**: `error: experimental Nix feature 'flakes' is disabled`

**Solution**:

```bash
# Add to ~/.config/nix/nix.conf
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

#### 2. Build fails due to unfree packages

**Error**: `Package 'xxx' has an unfree license`

**Solution**: Already enabled in `flake.nix` via:

```nix
nixpkgs.config.allowUnfree = true;
```

#### 3. Home Manager activation fails (既存ファイルの競合)

**Error**: `Existing file 'xxx' would be clobbered`

```
Existing file '/home/archie/.config/starship.toml' would be clobbered
Existing file '/home/archie/.config/gh/config.yml' would be clobbered
Existing file '/home/archie/.config/fish/config.fish' would be clobbered
```

これは Home Manager が管理したいファイルが既に存在していて、上書きしていいかわからないから止まっている状態。

**Solution**: `-b backup` オプションを使って既存ファイルを自動バックアップ:

```bash
nix run home-manager/master -- switch --flake .#archie -b backup
```

これで既存ファイルは `.backup` 拡張子付きでリネームされる（例: `starship.toml.backup`）。

**リストア方法**:

```bash
# バックアップから手動で戻す
mv ~/.config/starship.toml.backup ~/.config/starship.toml

# または Home Manager の世代でロールバック
home-manager generations
/nix/store/xxxxx-home-manager-generation/activate
```

#### 4. Package not found

**Error**: `attribute 'xxx' missing`

**Solution**: Search for the package:

```bash
# Search in nixpkgs
nix search nixpkgs xxx

# Or use online search
# https://search.nixos.org/packages
```

### Debug Tools

#### nix-tree

依存関係ツリーを可視化:

```bash
# Enter dev shell
nix develop

# View dependency tree
nix-tree
```

#### nix repl

Nix expressionを対話的に評価:

```bash
nix repl
> :l <nixpkgs>
> pkgs.hello
```

#### Verbose output

詳細なビルドログを表示:

```bash
nix build --show-trace --verbose .#homeConfigurations.archie.activationPackage
```

---

## 🔄 Migration from Shell Scripts

### Phase 1: Parallel Operation (Current)

現在は、Nixとシェルスクリプトベースのセットアップが並行して動作します:

- **Nix**: 推奨される新しい方法
- **Shell Scripts**: 後方互換性のために維持

どちらの方法も完全に機能します。

### Phase 2: Gradual Migration (Future)

今後、段階的に以下を移行予定:

1. ✅ パッケージ管理 (完了)
2. ⏳ CI/CD workflows (計画中)
3. ⏳ Docker環境 (計画中)
4. ⏳ Neovim plugins (オプション)

### Phase 3: Complete Transition (Long-term)

最終的には、すべての設定管理をNixに移行し、シェルスクリプトは削除予定です。

---

## 📚 Resources

### Official Documentation

- [Nix Manual](https://nixos.org/manual/nix/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Nixpkgs Manual](https://nixos.org/manual/nixpkgs/stable/)

### Community Resources

- [Nix Dev](https://nix.dev/)
- [Zero to Nix](https://zero-to-nix.com/)
- [Nix Pills](https://nixos.org/guides/nix-pills/)

### Search Tools

- [NixOS Search](https://search.nixos.org/)
- [Home Manager Options](https://nix-community.github.io/home-manager/options.html)

---

## 🤝 Contributing

Nixモジュールの改善や新しいモジュールの追加は大歓迎です！

1. Fork this repository
2. Create feature branch
3. Make your changes
4. Test with `home-manager switch --flake .#archie`
5. Submit pull request

---

## 📝 Notes

### Username Configuration

現在、`home.nix` ではハードコードされたユーザー名 `archie` を使用しています。
環境に応じて変更してください:

```nix
home.username = "your-username";  # Change this
home.homeDirectory = "/home/your-username";  # And this
```

### Existing Configuration Files

既存の `.config/` ディレクトリ内の設定ファイルは、`home.nix` でシンボリックリンクされています。
これにより、既存のカスタマイズを維持しながら、パッケージ管理をNixに移行できます。

### Platform Support

現在の設定は `x86_64-linux` をターゲットにしています。
他のプラットフォーム (macOS, ARM) のサポートも可能ですが、追加の設定が必要です。

---

**Happy Nix-ing! 🎉**
