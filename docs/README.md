# Documentation / ドキュメント

このディレクトリのドキュメントは [Diátaxis](https://diataxis.fr) フレームワークに沿って4つの象限に分類されています。「今なにをしたいか」によって見るべき場所が変わります。

| 象限 | 目的 | こんなときに |
|------|------|-------------|
| 🎓 **Tutorials** | 学習向け | まっさらな状態から手を動かして環境を作りたい |
| 🔧 **How-to** | 作業向け | すでに使っていて、特定の作業を済ませたい |
| 📖 **Reference** | 逆引き向け | 特定の情報（コマンド、キーバインド等）を調べたい |
| 💡 **Explanation** | 理解向け | なぜこの設計になっているのか背景を知りたい |

---

## 🎓 Tutorials / チュートリアル

学習向け。何も知らない状態から手を動かして環境を作り上げるための、順を追ったガイドです。

- [tutorials/getting-started.md](./tutorials/getting-started.md) - Nixのインストールから初回セットアップまで

---

## 🔧 How-to Guides / ハウツーガイド

作業向け。すでに基本を理解している人が、特定の目的を達成するためのガイドです。

- [how-to/install-and-update-packages.md](./how-to/install-and-update-packages.md) - パッケージの追加・更新・ロールバック
- [how-to/customize-your-fork.md](./how-to/customize-your-fork.md) - フォークして自分用にカスタマイズする
- [how-to/troubleshoot-nix.md](./how-to/troubleshoot-nix.md) - Nix関連のトラブルシューティング
- [how-to/run-with-docker.md](./how-to/run-with-docker.md) - Dockerでの動作確認
- [how-to/customize-keybindings.md](./how-to/customize-keybindings.md) - キーバインドの追加・変更
- [how-to/daily-workflow-commands.md](./how-to/daily-workflow-commands.md) - 日常的によく使うコマンド集
- [how-to/troubleshoot-fonts.md](./how-to/troubleshoot-fonts.md) - フォント関連のトラブルシューティング

---

## 📖 Reference / リファレンス

逆引き向け。特定の情報を調べるための技術的な一覧・仕様です。

- [reference/mise-tasks.md](./reference/mise-tasks.md) - mise タスク一覧
- [reference/directory-structure.md](./reference/directory-structure.md) - ディレクトリ構造
- [reference/nix-modules.md](./reference/nix-modules.md) - Nixモジュール構成
- [reference/keybindings.md](./reference/keybindings.md) - Fish/Tmux/Hyprlandのキーバインド
- [reference/neovim-config.md](./reference/neovim-config.md) - Neovimの設定ファイル構成とキーバインド
- [reference/ci-cd-pipeline.md](./reference/ci-cd-pipeline.md) - CI/CDパイプラインの仕様
- [reference/fontconfig.md](./reference/fontconfig.md) - フォント設定

---

## 💡 Explanation / 解説

理解向け。設計や背景にある「なぜ」を説明するドキュメントです。

- [explanation/architecture.md](./explanation/architecture.md) - 設計思想、Nix+Symlinkハイブリッドの理由
- [explanation/shell-boot-flow.md](./explanation/shell-boot-flow.md) - シェルの起動フローとBash/Fishの役割分担
- [explanation/cicd-evolution.md](./explanation/cicd-evolution.md) - CI/CDパイプラインの変遷と教訓
- [explanation/neovim-plugin-architecture.md](./explanation/neovim-plugin-architecture.md) - Neovimプラグイン構成の設計
- [explanation/daily-workflow-context.md](./explanation/daily-workflow-context.md) - 日々の作業内容と今後の展望

---

## 📖 Where to Start / どこから読むか

### 初めての方

1. **[explanation/architecture.md](./explanation/architecture.md)** - まずは設計思想を理解
2. **[tutorials/getting-started.md](./tutorials/getting-started.md)** - セットアップ方法とNixの使い方
3. **[reference/directory-structure.md](./reference/directory-structure.md)** - ディレクトリ構造を把握

### キーバインドを知りたい

- **[reference/keybindings.md](./reference/keybindings.md)** - Fish, Tmux, Hyprlandのショートカット
- **[reference/neovim-config.md](./reference/neovim-config.md)** - Neovimのキーバインドとプラグイン構成

### 特定のトピック

| 知りたいこと | ドキュメント |
|-------------|-------------|
| なぜNix + Symlinkなの？ | [explanation/architecture.md](./explanation/architecture.md) |
| Nixのインストール方法は？ | [tutorials/getting-started.md](./tutorials/getting-started.md) |
| パッケージの追加方法は？ | [how-to/install-and-update-packages.md](./how-to/install-and-update-packages.md#adding-new-packages) |
| ターミナルのショートカットは？ | [reference/keybindings.md](./reference/keybindings.md) |
| Neovimの使い方は？ | [reference/neovim-config.md](./reference/neovim-config.md) |
| ファイル構成を知りたい | [reference/directory-structure.md](./reference/directory-structure.md) |
| CI/CDでハマった問題を知りたい | [explanation/cicd-evolution.md](./explanation/cicd-evolution.md) |
| フォントがおかしいときは | [how-to/troubleshoot-fonts.md](./how-to/troubleshoot-fonts.md) |

---

## 📚 External Resources / 外部リソース

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

## 🔗 Related

- [../README.md](../README.md) - プロジェクト概要とクイックスタート
- [../CLAUDE.md](../CLAUDE.md) - Claude Code 向けコンテキスト
