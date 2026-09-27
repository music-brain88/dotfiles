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

ツールの管理層を移した後も、旧方式のインストール(化石)は端末に残ります。このリポジトリでは、その化石が PATH の先勝ちで新方式を隠す事故が実際に起きました(claude の npm 版残存、#584 の mise の curl installer 版残存)。

`~/.local/bin` と `~/.cargo/bin` は PATH の末尾に置いているので(#596、#611)、**この 2 つの化石が Nix 版を隠す事故は構造的に起きません**。原則は「Nix 版が常に勝つ」で、どちらも Nix に無いものだけを拾うフォールバック層です(優先順位の設計は [shell-boot-flow.md](../explanation/shell-boot-flow.md#path-の優先順位) を参照)。

それでも化石は掃除対象です。

- **静かに動かないだけになる**: Nix 版を隠さない代わりに、化石はエラーも出さずに残り続けます。気づくきっかけが無いので、見に行かないと溜まる一方です
- **Nix から外すと復活する**: `home.packages` からツールを外した瞬間、フォールバック層に残った化石が解決先になり、古いバージョンが黙って動き出します
- **末尾に回っていない場所の化石は今も隠せる**: npm グローバルの実体は mise の installs 配下に入り、hook-env がプロンプトのたびに PATH 先頭へ入れます(claude の npm 版残存はこの型)

症状と確認方法:

| 症状 | 確認コマンド | 期待値 |
|------|-------------|--------|
| claude の更新が来ない・バージョンがずれる | `readlink -f "$(which claude)"` | `~/.local/share/claude/versions/` 配下 |
| mise のバージョンが古い | `which mise` | `~/.nix-profile/bin/mise` |
| Nix で更新したのに反映されない | `type -a <tool>` | 先頭が `/nix/store/...`(`~/.nix-profile/bin` 経由)。先頭が mise installs 配下なら化石。`~/.cargo/bin` は末尾フォールバックなので Nix 版を隠さないが、`cargo install --list` に Nix と同名の crate が残っていれば掃除対象(#611) |
| `~/.local/bin` に置いたのに効かない | `type -a <tool>` | 先頭が `~/.local/bin/<tool>`。前に同名があれば、そちらが勝っている(末尾に置いているため) |
| `fishPlugins` で入れたプラグイン(bass 等、`nix/modules/shell.nix`)の挙動が Nix 版と違う | fish で `readlink -f (functions --details <関数名>)` | `/nix/store/…/share/fish/vendor_functions.d/` 配下。`~/.config/fish/functions/` の実体ファイルのままなら fisher 時代の化石(同じディレクトリでも `home.file` で置いたリポジトリ管理の関数は `/nix/store/` に解決されるので正常) |

掃除手順:

```bash
# npm グローバルの化石(claude 等)
mise x node -- npm ls -g --depth=0          # 残骸の確認
mise x node -- npm uninstall -g <package>

# cargo install の化石(Nix へ移したツールが ~/.cargo/bin に残っているもの)
cargo install --list                         # crate 名と入っているバイナリの対応。Nix と同名のものが掃除候補
cargo uninstall <crate>                      # 記録 (.crates.toml / .crates2.json) と同 crate の全バイナリを消す。Nix 側が引き継ぐ
# crate 名はバイナリ名と違うことがある: fd → fd-find, rg → ripgrep, delta → git-delta, dust → du-dust, btm → bottom, cargo-install-update → cargo-update

# #611 で洗い出した Nix と同名の 17 crate(バイナリ名は上の対応表を参照)。各マシンで手作業で実行する
cargo uninstall bat bottom cargo-update git-delta du-dust exa eza fd-find gitui \
  hyperfine oxker procs ripgrep skim starship tealdeer tokei

# curl installer の化石(mise 等、~/.local/bin に直接置かれたもの)
ls -la ~/.local/bin/                         # Nix 管理外の実体を確認
rm ~/.local/bin/<tool>                       # Nix に同名があれば解決先は既に Nix 版。無ければコマンドごと消える
```

> **⚠️ 注意:** `~/.local/bin` には Home Manager が意図的に置くファイル(`home.file` で定義、symlink になっている)もあります。`ls -la` で **symlink でない実体ファイル**だけが掃除候補です。消す前に `readlink` で確認してください。

> **⚠️ 壊れた cargo 版 hurl(#611):** `hurl` は Nix には無く、pacman 版(`/usr/bin/hurl`)と cargo 版が同名衝突しています。cargo 版(6.0.0)は `libxml2.so.2` が無く起動できないため、`~/.cargo/bin` が Nix より前にあった間は動かない cargo 版が動く pacman 版を隠していました。`~/.cargo/bin` を末尾に回した(#611)ことで `hurl` の解決先は pacman 版に戻ります。cargo 版は Nix と同名ではないので上記 17 crate には含みませんが、使わないなら `cargo uninstall hurl` で一緒に掃除してよいです。
>
> **⚠️ rustup proxy がある機での確認:** `~/.cargo/bin` に `cargo` / `rustc` / `rustup` の rustup proxy がある環境では、`--append` 後は `cargo` 自体の解決先も変わります。掃除の前後で `type -a cargo` を確認してください。

---

## 🔗 Related Documentation

- [tool-management-map.md](../reference/tool-management-map.md) — どのツールをどの層が管理するかの一覧と判断基準
- [getting-started.md](../tutorials/getting-started.md) — 新規マシンの初回セットアップ手順
- [install-and-update-packages.md](./install-and-update-packages.md) — Nix 管理パッケージの追加・更新
- [mise-tasks.md](../reference/mise-tasks.md) — mise タスク一覧(backup タスク含む)
