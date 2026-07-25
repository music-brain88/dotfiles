# Install Unmanaged Tools / Nix管理外ツールの導入

> **Diátaxis:** 🔧 How-to

`mise run nix:switch` では入らないツール(Nix 管理外)の導入・更新・掃除の手順です。どのツールがどの層で管理されているかの一覧と理由は [tool-management-map.md](../reference/tool-management-map.md) を参照してください。

---

## Claude Code の導入 / Install Claude Code

Claude Code は native installer 管理です(Nix にも npm にも入れない — 理由は [tool-management-map.md](../reference/tool-management-map.md) 参照)。

### 新規インストール

```bash
# Official native installer / 公式インストーラー
curl -fsSL https://claude.ai/install.sh | bash
```

### 確認

```bash
# ~/.local/bin/claude -> ~/.local/share/claude/versions/<ver> になっていれば正常
which claude
readlink -f "$(which claude)"
claude --version
```

`~/.claude.json` の `"installMethod"` が `"native"` になっていることも確認できます。更新は自動(`"autoUpdates": true`)なので、以降の手動操作は不要です。

### npm グローバルからの移行

過去の手順(npm グローバル)で導入した端末が残っている場合の移行手順です。native 版を先に入れ、動作確認してから npm 版を消します。

```bash
# 1. native 版を導入(npm 版の claude からでも install サブコマンドで移行できる)
claude install stable

# 2. native 版の動作確認
~/.local/bin/claude --version

# 3. npm 版を撤去
mise x node -- npm uninstall -g @anthropic-ai/claude-code

# 4. 新しいシェルで native 版に解決されることを確認
which claude   # => ~/.local/bin/claude
```

---

## OS層パッケージ / OS-layer Packages (Arch)

Window Manager・GUI 層(Hyprland, Waybar, WezTerm, Alacritty, Obsidian など)は Nix ではなく OS のパッケージマネージャ(pacman / paru)で導入します。設定ファイルだけを Nix が symlink します。

```bash
# バックアップ済みリストからの一括復元(mise run backup が書き出すリスト)
sudo pacman -S --needed - < .backup/pacman/pkglist.txt

# AUR パッケージは paru で個別に
paru -S <package>
```

> **Note:** `mise run backup` は明示インストール済みパッケージ一覧を `.backup/pacman/pkglist.txt` に退避します([mise-tasks.md](../reference/mise-tasks.md) 参照)。新端末セットアップ前に旧端末で実行しておくと復元がこの1行で済みます。

---

## トラブルシューティング / Troubleshooting

### 「化石」の検出と掃除

このリポジトリの歴史上、ツールの管理層が移行した後に**旧方式のインストールが端末に残り、PATH の先勝ちで新方式を隠す**事故が実際に起きています(claude の npm 版残存、mise の curl installer 版残存)。

症状と確認方法:

| 症状 | 確認コマンド | 期待値 |
|------|-------------|--------|
| claude の更新が来ない・バージョンがずれる | `readlink -f "$(which claude)"` | `~/.local/share/claude/versions/` 配下 |
| mise のバージョンが古い | `which mise` | `~/.nix-profile/bin/mise` |
| Nix で更新したのに反映されない | `which <tool>` | `/nix/store/...`(`~/.nix-profile/bin` 経由) |

掃除手順:

```bash
# npm グローバルの化石(claude 等)
mise x node -- npm ls -g --depth=0          # 残骸の確認
mise x node -- npm uninstall -g <package>

# curl installer の化石(mise 等、~/.local/bin に直接置かれたもの)
ls -la ~/.local/bin/                         # Nix 管理外の実体を確認
rm ~/.local/bin/<tool>                       # Nix 側 (~/.nix-profile/bin) が引き継ぐ
```

> **⚠️ 注意:** `~/.local/bin` には Home Manager が意図的に置くファイル(`home.file` で定義、symlink になっている)もあります。`ls -la` で **symlink でない実体ファイル**だけが掃除候補です。消す前に `readlink` で確認してください。

---

## 🔗 Related Documentation

- [tool-management-map.md](../reference/tool-management-map.md) — どのツールをどの層が管理するかの一覧と判断基準
- [getting-started.md](../tutorials/getting-started.md) — 新規マシンの初回セットアップ手順
- [install-and-update-packages.md](./install-and-update-packages.md) — Nix 管理パッケージの追加・更新
- [mise-tasks.md](../reference/mise-tasks.md) — mise タスク一覧(backup タスク含む)
