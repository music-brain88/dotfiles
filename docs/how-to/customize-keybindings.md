# Customize Keybindings / キーバインドのカスタマイズ

> **Diátaxis:** 🔧 How-to

Fish/Tmux/Hyprland にキーバインドを追加・変更する方法です。既存のキーバインド一覧は [reference/keybindings.md](../reference/keybindings.md) を参照してください。

---

## Adding Fish Keybindings

新しいキーバインドを追加する場合:

```fish
# .config/fish/functions/fish_user_key_bindings.fish
function fish_user_key_bindings
  # Ctrl+x で custom_function を実行
  bind \cx custom_function
end
```

## Adding Tmux Keybindings

```bash
# .tmux.conf
# prefix + x で custom command を実行
bind x run-shell "your-command"
```

## Adding Hyprland Keybindings

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
- [reference/directory-structure.md](../reference/directory-structure.md) - ディレクトリ構造
