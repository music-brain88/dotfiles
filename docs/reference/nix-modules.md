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

### herdr.nix

herdr (agent multiplexer、tmuxの後継):
- herdr パッケージ (flake.nix の overlay 経由で新しい nixpkgs から供給)
- `.config/herdr/config.toml` のシンボリックリンク (keybindは旧tmux設定互換)
- device-auth 承認URLをherdr-browser paneに直行させる `$BROWSER` ラッパー (Issue #523)

### neovim.nix

Neovim設定:
- Language servers (LSP)
- Formatters and linters
- Tree-sitter
- Python environment for Neovim

### dev-tools.nix

開発ツール:
- Container tools (Docker, lazydocker)
- Cloud tools (AWS CLI, Google Cloud SDK, OpenTofu, Ansible) — kubectl/k9s/helmはk8s-tools.nixに集約(下記参照)
- Database clients
- Language runtimes
- System monitoring tools

### k8s-tools.nix

Kubernetes / hexhive クラスタ運用ツール (dev-tools.nix からは分離し、k8s関連ツールをこのモジュールに集約):
- talosctl (Talos Linux CLI、hexhive ノード管理)
- kubectl, k9s (Kubernetes CLI/TUI)
- helm (Kubernetesパッケージ管理)
- sops, age (Secrets暗号化)

### fonts.nix

フォントパッケージ:
- hackgen-nf-font (等幅、ターミナル・エディタ用)
- source-han-sans, source-han-serif (システムUI用)
- noto-fonts-color-emoji (絵文字フォールバック用)

### desktop.nix

ネイティブArch (Hyprland) 専用のGUI設定群 (WSL profileではimportされない):
- Hyprland, systemd user units (Hyprlandセッションターゲット)
- Waybar, Wofi, Mako
- WezTerm (メインターミナル), Alacritty (併存期間中のフォールバック)
- MPD, ncmpcpp, fontconfig

### wsl.nix

WSL固有の設定 (wsl profileのみ):
- Obsidian vault symlink (実体はWindows側、Cowork/Obsidian Syncの都合)
- WezTerm/Alacritty設定のWindows側への配布 (drift防止、activation時にコピー)

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
