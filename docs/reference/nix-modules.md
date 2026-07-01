# Nix Modules / Nixモジュール構成

> **Diátaxis:** 📖 Reference

このドキュメントでは、`nix/modules/` 配下のNixモジュール構成を説明します。なぜこのように分割されているかは [architecture.md](../explanation/architecture.md) を参照してください。

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

## 📝 Notes

### Username Configuration

現在、`home.nix` ではハードコードされたユーザー名 `archie` を使用しています。
環境に応じて変更してください（手順は [customize-your-fork.md](../how-to/customize-your-fork.md) を参照）:

```nix
home.username = "your-username";  # Change this
home.homeDirectory = "/home/your-username";  # And this
```

### Platform Support

現在の設定は `x86_64-linux` をターゲットにしています。
他のプラットフォーム (macOS, ARM) のサポートも可能ですが、追加の設定が必要です。

---

## 🔗 Related Documentation

- [architecture.md](../explanation/architecture.md) - モジュール分割の設計思想
- [customize-your-fork.md](../how-to/customize-your-fork.md) - 新しいモジュールの作成方法
- [directory-structure.md](./directory-structure.md) - ディレクトリ構造
