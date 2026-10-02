# Customize Keybindings / キーバインドのカスタマイズ

> **Diátaxis:** 🔧 How-to

Fish/herdr/Tmux/Hyprland にキーバインドを追加・変更する方法です。既存のキーバインド一覧は [reference/keybindings.md](../reference/keybindings.md) を参照してください。

---

## Adding Fish Keybindings

Fish に新しいキーバインドを追加する場合は、`.config/fish/functions/fish_user_key_bindings.fish` の `fish_user_key_bindings` 関数に `bind` を書きます。次の例は `Ctrl+x` に `custom_function` を割り当てます。

```fish
# .config/fish/functions/fish_user_key_bindings.fish
function fish_user_key_bindings
  # Ctrl+x で custom_function を実行
  bind \cx custom_function
end
```

## Adding herdr Keybindings

herdr のキーバインドは `.config/herdr/config.toml` の `[keys]` テーブルで宣言します。現在の割当と 4 層ナビゲーションの全体像は [reference/keybindings.md の herdr 節](../reference/keybindings.md#-herdr) を参照してください。

```toml
# .config/herdr/config.toml
[keys]
prefix = "ctrl+g"                             # prefix キー (herdr のデフォルトは ctrl+b)
split_vertical = ["prefix+v", "prefix+|"]     # 配列で複数キーを割り当て
new_workspace = "prefix+shift+c"              # 修飾キーは + でつなぐ
switch_workspace = "prefix+shift+1..9"        # 1..9 で番号付き (indexed) 割当

# 例: close_pane (デフォルト prefix+x) を残したまま prefix+ctrl+x も割り当てる
# close_pane = ["prefix+x", "prefix+ctrl+x"]
```

- **キー名はアクション名**: 左辺は `split_vertical` / `next_tab` / `reload_config` などの herdr のアクション名で、右辺はキーです。キーは `prefix+<key>` の形で書き、修飾キーは `shift` / `ctrl` / `alt` を `+` でつなぎます(herdr のデフォルト設定では `-` キーを `minus` と表記しています。例: `split_horizontal = "prefix+minus"`)。書式の誤りは、後の手順 2 の `herdr config check` で検出できます。
- **書いたアクションだけデフォルトを上書きする**: `[keys]` に書かなかったアクションは、herdr のデフォルトのまま効きます。このリポジトリでデフォルトのまま使っているもの(`focus_pane_*` = `prefix+h/j/k/l`、`copy_mode` = `prefix+[`、`reload_config` = `prefix+shift+r` など)は、config.toml 冒頭 1〜17 行目のコメントに一覧があります。デフォルトのキーを残したまま別キーを足したいときは、`split_vertical` のようにデフォルトのキーも配列に含めます。
- **旧 tmux との対応**: config.toml の各行の末尾コメントには、対応する tmux の設定を併記しています。新しく足す行も同じ流儀で書きます。

config.toml は Nix(`nix/modules/herdr.nix`)が `~/.config/herdr/config.toml` へ配布しているため、`~/.config` 側ではなくリポジトリ側を編集して反映します。

```bash
# 1. リポジトリ側の .config/herdr/config.toml を編集したら反映
mise run nix:switch

# 2. 配布された config.toml を検証
herdr config check

# 3. 起動中の herdr に読み込ませる (prefix + shift + r でも同じ)
herdr server reload-config
```

反映後は `prefix + ?` で全キーバインド一覧を表示して確認できます。

## Adding Tmux Keybindings

> **Note**: Tmux は herdr への移行中で非推奨です。新しいキーバインドは原則 herdr 側に追加してください。

Tmux のキーバインドは、`.config/tmux/tmux.conf` に `bind` で追加します。

```bash
# .config/tmux/tmux.conf (Nix が ~/.tmux.conf へ配布)
# prefix + x で custom command を実行
bind x run-shell "your-command"
```

## Adding Hyprland Keybindings

Hyprland のキーバインドは、`.config/hypr/keybinds.conf` に `bind` で追加します。次のコードブロックの後半は、サブマップ(モード)を使う場合の書き方です。

```bash
# .config/hypr/keybinds.conf
# Super + x でカスタムコマンドを実行
bind = $mainMod, X, exec, your-command

# サブマップ（モード）を使う場合
bind = $mainMod, X, submap, mymode
submap = mymode
bind = , A, exec, command-a
bind = , Escape, submap, reset
submap = reset
```

---

## 🔗 Related Documentation

- [reference/keybindings.md](../reference/keybindings.md) - 既存のキーバインド一覧
- [reference/keybindings.md の herdr 節](../reference/keybindings.md#-herdr) - herdr の現在の割当と 4 層ナビゲーション
- [reference/directory-structure.md](../reference/directory-structure.md) - ディレクトリ構造
