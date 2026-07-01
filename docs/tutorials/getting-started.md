# Getting Started / はじめてのセットアップ

> **Diátaxis:** 🎓 Tutorial

このチュートリアルでは、このdotfilesリポジトリを使って、まっさらな環境からNix + Home Managerで開発環境を構築するまでの手順を説明します。

このリポジトリは **Nix Flakes + Home Manager + mise** を使用して、宣言的で再現可能な開発環境を提供します。

- **Nix/Home Manager**: パッケージ管理と環境設定
- **mise**: タスクランナー（ビルド、デプロイなどのコマンドを簡単に実行）

なぜこの構成を採用しているかは [architecture.md](../explanation/architecture.md) を参照してください。

---

## 1. Install Nix

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

## 2. Verify Installation

```bash
nix --version
```

## 3. Clone Repository

```bash
git clone https://github.com/music-brain88/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

## 4. Build and Activate

```bash
# Recommended: Use home-manager directly
home-manager switch --flake .#archie

# If home-manager is not installed yet
nix run home-manager/master -- switch --flake .#archie

# Alternative: Manual build and activate
nix build .#homeConfigurations.archie.activationPackage
./result/activate
```

同じことは `mise run nix:switch` でも実行できます。タスクの一覧は [mise-tasks.md](../reference/mise-tasks.md) を参照してください。

### Flake URL の構文について

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
home-manager switch --flake github:music-brain88/dotfiles#archie

# パスを指定する場合
home-manager switch --flake /path/to/dotfiles#archie
```

## 5. Install Neovim Plugins

```bash
nvim --headless +"call dein#install()" +qall
```

---

## Next Steps

- 自分用にユーザー名などをカスタマイズしたい → [customize-your-fork.md](../how-to/customize-your-fork.md)
- パッケージを追加・更新したい → [install-and-update-packages.md](../how-to/install-and-update-packages.md)
- うまく動かないときは → [troubleshoot-nix.md](../how-to/troubleshoot-nix.md)
- キーバインドを知りたい → [keybindings.md](../reference/keybindings.md)

---

## 🔗 Related Documentation

- [architecture.md](../explanation/architecture.md) - Nix + Symlinkハイブリッドの設計思想
- [nix-modules.md](../reference/nix-modules.md) - Nixモジュール構成
- [directory-structure.md](../reference/directory-structure.md) - ディレクトリ構造
