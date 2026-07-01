# Keybindings / キーバインド

> **Diátaxis:** 📖 Reference

このドキュメントでは、dotfilesリポジトリで設定されているキーバインドとショートカットを説明します。

---

## 📚 Table of Contents

- [Fish Shell](#fish-shell)
- [Tmux](#tmux)
- [Hyprland](#hyprland)
- [Neovim](#neovim) *(separate document)*
- [Shell Aliases](#shell-aliases)

---

## 🐟 Fish Shell

Fish shellのキーバインドは `.config/fish/functions/fish_user_key_bindings.fish` で定義されています。

### Fuzzy Finder (skim)

[skim](https://github.com/lotabout/skim) を使ったファジーファインダー連携。

| Keybind | Description | 説明 |
|---------|-------------|------|
| `Ctrl+t` | File search with preview | ファイル検索（プレビュー付き） |
| `Ctrl+r` | Command history search | コマンド履歴検索 |
| `Alt+d` | Directory search | ディレクトリ検索・移動 |

### Git Integration

| Keybind | Description | 説明 |
|---------|-------------|------|
| `Ctrl+y` | Git branch checkout with skim | ブランチをskim選択してcheckout |

### Docker Integration

| Keybind | Description | 説明 |
|---------|-------------|------|
| `,d` | Select Docker container and show logs | Dockerコンテナ選択＆ログ表示 |

### skim Tips

- `Ctrl+t` のファイル検索では `bat` によるシンタックスハイライト付きプレビューが表示される
- `Ctrl+y` のブランチ選択では最新20件のコミットログがプレビュー表示される
- `,d` のDocker選択では `p` キーでプレビュー（ログ）の表示/非表示を切り替え

---

## 🖥️ Tmux

Tmuxの設定は `.tmux.conf` で定義されています。

### Prefix Key

デフォルトの `Ctrl+b` から変更されています。

| Key | Description |
|-----|-------------|
| `Ctrl+g` | Prefix key (prefixキー) |

### Pane Operations

| Keybind | Description | 説明 |
|---------|-------------|------|
| `prefix + \|` | Split pane vertically | ペインを縦に分割 |
| `prefix + -` | Split pane horizontally | ペインを横に分割 |

### Pane Navigation (Vim-style)

| Keybind | Description | 説明 |
|---------|-------------|------|
| `prefix + h` | Move to left pane | 左のペインへ移動 |
| `prefix + j` | Move to bottom pane | 下のペインへ移動 |
| `prefix + k` | Move to top pane | 上のペインへ移動 |
| `prefix + l` | Move to right pane | 右のペインへ移動 |

### Window Navigation

| Keybind | Description | 説明 |
|---------|-------------|------|
| `prefix + Ctrl+h` | Previous window | 前のウィンドウへ |
| `prefix + Ctrl+l` | Next window | 次のウィンドウへ |

### Pane Resizing

| Keybind | Description | 説明 |
|---------|-------------|------|
| `prefix + H` | Resize pane left (5 cells) | ペインを左に5セル拡大 |
| `prefix + J` | Resize pane down (5 cells) | ペインを下に5セル拡大 |
| `prefix + K` | Resize pane up (5 cells) | ペインを上に5セル拡大 |
| `prefix + L` | Resize pane right (5 cells) | ペインを右に5セル拡大 |

### Utility

| Keybind | Description | 説明 |
|---------|-------------|------|
| `prefix + r` | Reload tmux config | 設定ファイルをリロード |

### Copy Mode

コピーモードはviキーバインドを使用。

| Keybind | Description | 説明 |
|---------|-------------|------|
| `v` | Begin selection | 選択開始 |
| `y` | Copy to clipboard | クリップボードにコピー |
| Scroll up | Enter copy mode | コピーモードに入る |

### Mouse Support

マウス操作が有効化されています。スクロールでコピーモードに入り、最後までスクロールダウンすると自動的に抜けます。

---

## 🪟 Hyprland

Hyprlandの設定は `.config/hypr/keybinds.conf` で定義されています。

> **Note**: メインの修飾キーは `Super` (Windowsキー) です。以下では `Super` と表記します。

### Application Launcher

| Keybind | Description | 説明 |
|---------|-------------|------|
| `Super + Enter` | Open terminal (Alacritty) | ターミナルを開く |
| `Super + D` | Application launcher (Wofi) | アプリランチャー |
| `Super + Space` | Application launcher (Wofi) | アプリランチャー（代替） |
| `Super + I` | Open browser (Vivaldi) | ブラウザを開く |
| `Super + E` | Open file manager (Nautilus) | ファイルマネージャーを開く |
| `Super + L` | Lock screen (Hyprlock) | 画面をロック |
| `Super + M` | Logout menu (Wlogout) | ログアウトメニュー |

### Window Management

| Keybind | Description | 説明 |
|---------|-------------|------|
| `Alt + F4` | Close active window | アクティブウィンドウを閉じる |
| `Super + V` | Toggle floating mode | フローティングモード切り替え |
| `Super + P` | Toggle pseudo-tiling | 疑似タイリング切り替え |
| `Super + J` | Toggle split direction | 分割方向を切り替え |
| `Super + F` | Toggle fullscreen | フルスクリーン切り替え |

### Window Focus

| Keybind | Description | 説明 |
|---------|-------------|------|
| `Super + ←` | Focus left | 左のウィンドウにフォーカス |
| `Super + →` | Focus right | 右のウィンドウにフォーカス |
| `Super + ↑` | Focus up | 上のウィンドウにフォーカス |
| `Super + ↓` | Focus down | 下のウィンドウにフォーカス |
| `Alt + Tab` | Window switcher | ウィンドウ切り替え |
| `Alt + Shift + Tab` | Window switcher (reverse) | ウィンドウ切り替え（逆順） |

### Window Movement

| Keybind | Description | 説明 |
|---------|-------------|------|
| `Super + Shift + ←` | Move window left | ウィンドウを左に移動 |
| `Super + Shift + →` | Move window right | ウィンドウを右に移動 |
| `Super + Shift + ↑` | Move window up | ウィンドウを上に移動 |
| `Super + Shift + ↓` | Move window down | ウィンドウを下に移動 |
| `Super + 左ドラッグ` | Move window (mouse) | マウスでウィンドウを移動 |
| `Super + 右ドラッグ` | Resize window (mouse) | マウスでウィンドウをリサイズ |

### Window Resize Mode

`Super + R` でリサイズモードに入ります。

| Keybind | Description | 説明 |
|---------|-------------|------|
| `←` | Resize left (-10px) | 左に縮小 |
| `→` | Resize right (+10px) | 右に拡大 |
| `↑` | Resize up (-10px) | 上に縮小 |
| `↓` | Resize down (+10px) | 下に拡大 |
| `Enter` / `Escape` | Exit resize mode | リサイズモード終了 |

### Workspace Navigation

| Keybind | Description | 説明 |
|---------|-------------|------|
| `Super + 1-9, 0` | Switch to workspace 1-10 | ワークスペース1-10に移動 |
| `Super + Shift + 1-9, 0` | Move window to workspace 1-10 | ウィンドウをワークスペース1-10に移動 |
| `Super + Tab` | Toggle previous workspace | 直前のワークスペースとトグル |
| `Super + S` | Toggle special workspace | スクラッチパッドの表示/非表示 |
| `Super + Alt + S` | Move window to special workspace | ウィンドウをスクラッチパッドへ送る |

### Screenshot

| Keybind | Description | 説明 |
|---------|-------------|------|
| `Print` | Screenshot (region to clipboard) | 選択領域をクリップボードにコピー |
| `Super + Shift + S` | Screenshot (region to file) | 選択領域をファイルに保存 |
| `Shift + Print` | Screenshot (region to file) | 選択領域をファイルに保存 |

### Media Controls

| Keybind | Description | 説明 |
|---------|-------------|------|
| `XF86AudioRaiseVolume` | Volume up (+5%, hold to repeat) | 音量アップ（長押しリピート対応） |
| `XF86AudioLowerVolume` | Volume down (-5%, hold to repeat) | 音量ダウン（長押しリピート対応） |
| `XF86AudioMute` | Toggle mute | ミュート切り替え |
| `XF86AudioPlay` | Play / pause (playerctl) | 再生 / 一時停止 |
| `XF86AudioNext` | Next track | 次のトラック |
| `XF86AudioPrev` | Previous track | 前のトラック |
| `XF86MonBrightnessUp` | Brightness up (+5%, hold to repeat) | 明るさアップ（長押しリピート対応） |
| `XF86MonBrightnessDown` | Brightness down (-5%, hold to repeat) | 明るさダウン（長押しリピート対応） |

### System Management

| Keybind | Description | 説明 |
|---------|-------------|------|
| `Super + Shift + P` | Package manager (paru) | パッケージマネージャーを開く |
| `Super + N` | Toggle notifications | 通知のトグル |
| `Super + Shift + N` | Clear notifications | 通知をクリア |
| `Super + Shift + V` | Clipboard history (cliphist) | クリップボード履歴から選んでコピー |

---

## 📝 Neovim

Neovimのキーバインドは量が多いため、別ドキュメントにまとめています。

👉 **[neovim-config.md](./neovim-config.md#keybindings)** - Neovim キーバインド・設定リファレンス

### Quick Reference

| Category | Key Examples | Description |
|----------|--------------|-------------|
| **Buffer** | `Ctrl+j/k` | バッファ切り替え |
| **Filer** | `,m` | ファイラーを開く |
| **Search** | `,g`, `,b`, `,w` | 全文検索、バッファ、grep |
| **LSP** | `gd`, `gr`, `gh` | 定義、参照、ホバー |
| **Copilot** | `<leader>c*` | CopilotChat機能 |
| **Comment** | `gc`, `gcc` | コメントトグル |
| **Surround** | `sa`, `sd`, `sr` | 囲み操作 |

---

## 🔧 Shell Aliases

`.config/fish/config.fish` で定義されているエイリアス。

### Editor

| Alias | Command | Description |
|-------|---------|-------------|
| `vim` | `nvim` | Neovimをvimコマンドで起動 |

### Modern CLI Replacements

モダンなCLIツールが自動的にエイリアスされます（インストールされている場合）。

| Alias | Replacement | Description |
|-------|-------------|-------------|
| `ls` | `eza --icons` | ファイル一覧（アイコン付き） |
| `cat` | `bat` | ファイル表示（シンタックスハイライト付き） |
| `ps` | `procs` | プロセス一覧（カラフル表示） |

### Utility Functions

| Command | Description |
|---------|-------------|
| `reload` | Fish shellをリロード |

---

## 🔗 Related Files

| File | Description |
|------|-------------|
| `.config/fish/functions/fish_user_key_bindings.fish` | Fish キーバインド定義 |
| `.config/fish/config.fish` | Fish 基本設定・エイリアス |
| `.tmux.conf` | Tmux 設定 |
| `.config/hypr/keybinds.conf` | Hyprland キーバインド定義 |
| `.config/hypr/hyprland.conf` | Hyprland メイン設定 |

キーバインドを追加・変更したい場合は [customize-keybindings.md](../how-to/customize-keybindings.md) を参照してください。

---

## 🔗 Related Documentation

- [README.md](../../README.md) - プロジェクト概要
- [directory-structure.md](./directory-structure.md) - ディレクトリ構造
- [getting-started.md](../tutorials/getting-started.md) - Nix/Home Manager ガイド
