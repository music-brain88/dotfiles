# Nix Modules / Nixモジュール構成

> **Diátaxis:** 📖 Reference

このドキュメントでは、`nix/modules/` 配下のNixモジュール構成を説明します。なぜこのように分割されているかは [architecture.md](../explanation/architecture.md) を参照してください。

---

## 📂 Module Structure

### base.nix

`base.nix` は、最小構成の基本的なシステムパッケージを定義します。curl/wget/cmakeはdev-tools.nixへ、gitはgit.nixへ、pkg-configはrust-tools.nixへ移動済みです。
- gnutar, gzip
- protobuf
- mako, libnotify
- wl-clipboard, cliphist, hypridle
- tree, which, file

### rust-tools.nix

`rust-tools.nix` は、Rust開発ツールとCLIツールを定義します。
- rustup, cargo
- fd, ripgrep, eza, bat
- gitui, tealdeer, hyperfine

### shell.nix

`shell.nix` は、Fish shellとStarshipを設定します。
- Fish shell with plugins (z, bass)
- Starship prompt configuration
- Shell aliases and functions

### git.nix

`git.nix` は、Git の次の項目を設定します。
- User information
- Aliases
- Delta (better diff viewer)
- GitHub CLI (gh)

### tmux.nix

`tmux.nix` は、Tmux の次の項目を設定します。
- Key bindings
- Status bar configuration
- Plugins (sensible, yank, resurrect, etc.)

### herdr.nix

`herdr.nix` は、herdr (agent multiplexer、tmuxの後継) に関する次の 4 つを管理します。
- herdr パッケージ (flake.nix の overlay 経由で新しい nixpkgs から供給)
- `.config/herdr/config.toml` のシンボリックリンク (keybindは旧tmux設定互換)
- device-auth 承認URLをherdr-browser paneに直行させる `$BROWSER` ラッパー (Issue #523)
- herdr-browser 用の環境変数 `HERDR_BROWSER_TRANSPORT`・`HERDR_BROWSER_CELL_WIDTH`・`HERDR_BROWSER_CELL_HEIGHT` を `home.sessionVariables` で宣言する (Issue #693, #699)。

### neovim.nix

`neovim.nix` は、Neovim の次の要素を設定します。
- Language servers (LSP)
- Formatters and linters
- Tree-sitter
- Python environment for Neovim

### dev-tools.nix

`dev-tools.nix` は、次の開発ツールを定義します。
- Container tools (Docker, lazydocker)
- Cloud tools (AWS CLI, Google Cloud SDK, OpenTofu, Ansible) — kubectl/k9s/helmはk8s-tools.nixに集約(「k8s-tools.nix」節参照)
- Database clients
- Language runtimes
- System monitoring tools

### k8s-tools.nix

`k8s-tools.nix` は、Kubernetes / hexhive クラスタの運用ツールを定義します。k8s関連ツールは dev-tools.nix から分離し、このモジュールに集約しています。
- talosctl (Talos Linux CLI、hexhive ノード管理)
- kubectl, k9s (Kubernetes CLI/TUI)
- helm (Kubernetesパッケージ管理)
- sops, age (Secrets暗号化)

### fonts.nix

`fonts.nix` は、次のフォントパッケージを定義します。
- hackgen-nf-font (等幅、ターミナル・エディタ用)
- source-han-sans, source-han-serif (システムUI用)
- noto-fonts-color-emoji (絵文字フォールバック用)

### desktop.nix

`desktop.nix` は、ネイティブArch (Hyprland) 専用のGUI設定群を定義します (WSL profileではimportされません)。
- Hyprland, systemd user units (Hyprlandセッションターゲット)
- Waybar, Wofi, Mako
- WezTerm (メインターミナル), Alacritty (併存期間中のフォールバック)
- MPD, ncmpcpp, fontconfig

### wsl.nix

`wsl.nix` は、WSL固有の設定を定義します (wsl profileでのみ使います)。
- Obsidian vault symlink (実体はWindows側、Cowork/Obsidian Syncの都合)
- WezTerm/Alacritty設定のWindows側への配布 (drift防止、activation時にコピー)

---

## 📝 Notes

### Username Configuration

現在、`home.nix` ではハードコードされたユーザー名 `archie` を使用しています。
利用者は、環境に応じて次の 2 行を変更してください（手順は [customize-your-fork.md](../how-to/customize-your-fork.md) を参照）。

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
