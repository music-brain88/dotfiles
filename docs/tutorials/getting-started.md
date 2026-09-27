# Getting Started / はじめてのセットアップ

> **Diátaxis:** 🎓 Tutorial

このチュートリアルでは、このdotfilesリポジトリを使って、まっさらな環境からNix + Home Managerで開発環境を構築するまでの手順を説明します。

このリポジトリは **Nix Flakes + Home Manager + mise** を使用して、宣言的で再現可能な開発環境を提供します。

- **Nix/Home Manager**: パッケージ管理と環境設定
- **mise**: タスクランナー（ビルド、デプロイなどのコマンドを簡単に実行）

なぜこの構成を採用しているかは [architecture.md](../explanation/architecture.md) を参照してください。

---

## 0. Prerequisites / 前提

リポジトリの clone に `git` が必要です。Arch Linux の場合は OS のパッケージマネージャで導入します:

```bash
sudo pacman -S git
```

> **Note:** Window Manager や GUI 層(Hyprland, WezTerm など)も Nix ではなく OS 側(pacman / paru)で導入します。どのツールがどの層の管理かは [tool-management-map.md](../reference/tool-management-map.md) を参照してください。

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

> **Note:** タスクランナーの mise 自体も Nix が導入します(`programs.mise`)。そのため**初回だけ**は上記のように home-manager を直接実行します。switch が完走した後は、同じことが `mise run nix:switch` で実行できます。タスクの一覧は [mise-tasks.md](../reference/mise-tasks.md) を参照してください。

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

Neovim のプラグインは**初回起動時に自動でインストール**されます(プラグインマネージャは dpp.vim)。インストール用のコマンドを打つ必要はなく、Neovim を起動するだけです:

```bash
nvim
```

初回起動では次の順で進みます:

1. `init.lua` が dpp の state(`~/.cache/dpp` 配下の `startup.vim` / `state.vim`)を生成する
2. プラグインが1つも取得されていないことを検知し、`:DppInstall` 相当の処理を自動で開始する(通知が出ます。数分かかることがあります)
3. `dpp: initial plugin install finished. Restart Neovim to load them.` と通知されたら、Neovim を再起動する(手順1の直後に出る `dpp#make_state() done. Restart Neovim to load plugins.` の時点ではまだインストール中なので、こちらの通知を待ちます)

> **Note:** 起動時に `dpp.vim: NVIM_DPP_*/NVIM_DENOPS_VIM environment variables are not set.` と表示された場合は、手順4で追加された環境変数がまだシェルに読み込まれていません。再ログイン(または新しいシェルを開く)してから Neovim を起動し直してください。

- 自動インストールが途中で止まった・プラグインを入れ直したいときは、Neovim 内で `:DppInstall` を実行します
- TOML を変更した後の反映は通常自動で行われます。Neovim を開かずに明示的に反映したいときは `mise run nvim:state` を実行します

仕組みの詳細は [neovim-config.md の Plugin Management (dpp)](../reference/neovim-config.md#-plugin-management-dpp) を参照してください。

## 6. Install Claude Code (Optional)

Claude Code は Nix 管理外(native installer 管理)なので、別途導入します:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

以降の更新は自動です。詳細な確認手順や npm 版からの移行は [install-unmanaged-tools.md](../how-to/install-unmanaged-tools.md) を参照してください。

---

## Next Steps

- 自分用にユーザー名などをカスタマイズしたい → [customize-your-fork.md](../how-to/customize-your-fork.md)
- どのツールがどの層で管理されているか知りたい → [tool-management-map.md](../reference/tool-management-map.md)
- パッケージを追加・更新したい → [install-and-update-packages.md](../how-to/install-and-update-packages.md)
- うまく動かないときは → [troubleshoot-nix.md](../how-to/troubleshoot-nix.md)
- キーバインドを知りたい → [keybindings.md](../reference/keybindings.md)

---

## 🔗 Related Documentation

- [architecture.md](../explanation/architecture.md) - Nix + Symlinkハイブリッドの設計思想
- [nix-modules.md](../reference/nix-modules.md) - Nixモジュール構成
- [directory-structure.md](../reference/directory-structure.md) - ディレクトリ構造
