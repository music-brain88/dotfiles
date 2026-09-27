# Shell Configuration / シェル設定

> **Diátaxis:** 💡 Explanation

このドキュメントでは、シェル環境の構成と設計思想について説明します。

---

## 📚 Table of Contents

- [Background](#background)
- [Boot Flow](#boot-flow)
- [File Responsibilities](#file-responsibilities)
- [Why This Architecture](#why-this-architecture)

---

## 🎯 Background

### なぜ Fish をログインシェルにしないのか？

Fish は素晴らしいインタラクティブシェルですが、**POSIX 非互換**という特徴があります。

```bash
# POSIX シェル (bash, zsh, sh)
export FOO=bar
if [ "$x" = "y" ]; then ...

# Fish
set -x FOO bar
if test "$x" = "y"; ...
```

多くのシステムツールやスクリプトは POSIX シェルを前提としているため、Fish をログインシェルに設定すると問題が発生することがあります：

- `/etc/profile` や `/etc/profile.d/*` のスクリプトが正しく実行されない
- 一部の環境変数が設定されない
- SSH 接続時のスクリプト互換性問題

### 解決策：Bash をブートストラップとして使用

```
ログインシェル（Bash）
    ↓
環境変数の設定（POSIX 互換）
    ↓
exec fish（プロセス置換）
    ↓
Fish で作業
```

この構成により、POSIX 互換性を保ちながら Fish の快適な操作性を享受できます。

---

## 🔄 Boot Flow

### シェル起動の流れ

```
┌─────────────────────────────────────────────────────────┐
│                    Terminal Launch                      │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│  .bash_profile                                          │
│  └── source ~/.bashrc                                   │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│  .bashrc                                                │
│  ├── 非インタラクティブなら終了                         │
│  ├── Nix 環境の source (nix.sh)                         │
│  ├── ssh-agent 起動（未起動の場合）                     │
│  ├── GPG_TTY 設定                                       │
│  ├── gpg-agent の tty 更新（SSH接続時）                 │
│  └── exec fish                                          │
└────────────────────────┬────────────────────────────────┘
                         │
                         │  exec = プロセス置換
                         │  （Bash プロセスが Fish に置き換わる）
                         ▼
┌─────────────────────────────────────────────────────────┐
│  config.fish                                            │
│  ├── ロケール設定 (LANG, LC_CTYPE)                      │
│  ├── PATH 設定 (~/.local/bin, cargo, go, etc.)          │
│  ├── エイリアス設定 (vim, rm, ls, cat, ps)              │
│  ├── プロンプト設定 (starship)                          │
│  └── ツール有効化 (mise)                                │
└─────────────────────────────────────────────────────────┘
```

### `exec` コマンドについて

`exec fish` は新しいプロセスを fork するのではなく、現在の Bash プロセスを Fish で**置き換え**ます。

```bash
# exec なし（fork）
bash (PID 100)
  └── fish (PID 101)  # 子プロセス、bash も残る

# exec あり（置換）
bash (PID 100) → fish (PID 100)  # 同じ PID、bash は消える
```

**重要**: `exec` 以降のコードは実行されません。環境変数の設定は `exec` の前に行う必要があります。

---

## 📁 File Responsibilities

### 各ファイルの責務

| File | Purpose | Managed by |
|------|---------|------------|
| `.bash_profile` | ログインシェル起動時に `.bashrc` を読み込む | dotfiles |
| `.bashrc` | 最小限のブートストラップ、`exec fish` | dotfiles |
| `config.fish` | メインの設定（PATH、エイリアス、プロンプト等） | dotfiles + Nix |

### .bashrc の責務（最小限）

```bash
# 1. 非インタラクティブなら何もしない
[ -z "$PS1" ] && return

# 2. Nix 環境の source（Nix 管理下の fish を起動するために必須）
if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

# 3. 環境変数の設定（exec で引き継がれる）
if [ "$(uname -s)" = 'Linux' ]; then
  # ssh-agent（既に起動中なら何もしない）
  if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)"
  fi
  export GPG_TTY=$(tty)
  # SSH 接続時は gpg-agent が保持する tty を更新する
  if [ -n "$SSH_CONNECTION" ]; then
    gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
  fi
fi

# 4. Fish を起動
exec fish
```

### config.fish の責務

```fish
# ロケール
set -x LANG en_US.UTF-8
set -x LC_CTYPE en_US.UTF-8

# エイリアス
alias vim 'nvim'
alias rm 'rm -i'

# PATH 設定（fish_add_path --path で冪等に追加。理由は下記）
set -x PYENV_ROOT $HOME/.pyenv
fish_add_path --path $PYENV_ROOT/bin
set -gx PATH (string match -v -- $HOME/.cargo/bin $PATH)
fish_add_path --path --append $HOME/.cargo/bin # deno / zellij / broot 等 cargo install 専用ツール（末尾。理由は下記）
fish_add_path --path $HOME/.pulumi/bin
set -gx PATH (string match -v -- $HOME/.local/bin $PATH)
fish_add_path --path --append $HOME/.local/bin # claude 等 native installer 管理ツール（末尾。理由は下記）
set -x GOPATH $HOME/go
fish_add_path --path --append $GOPATH/bin      # go も末尾（低優先度）

# モダン CLI ツール
if type -q eza; alias ls 'eza --icons'; end
if type -q bat; alias cat 'bat'; end

# プロンプト
starship init fish | source           # 生成時の starship 絶対パスを fish_prompt 等に焼き込む(掃除時は exec fish が必要 → docs/how-to/install-unmanaged-tools.md)

# バージョン管理
mise activate fish | source
```

### PATH は `fish_add_path --path` で書く

fish は入れ子で起動されるたびに（herdr の pane → 作業者 → Claude Code など）config.fish を頭から実行し直します。そのため PATH の追加は、何度実行しても結果が変わらない（冪等な）書き方にしています。

| 書き方 | 入れ子で起動したときの PATH |
|--------|------------------------------|
| `set -x PATH X $PATH` | 実行のたびに先頭へ足すので、段数ぶん同じ dir が積み上がる（3 段で `~/.cargo/bin` が 6 回、31 要素） |
| `fish_add_path --path X` | 既にあれば何もしない。段数によらず一定（1 段でも 3 段でも 15 要素、重複なし） |

- **`--path` は必須**: 付けないと universal 変数 `fish_user_paths`（`~/.config/fish/fish_variables`、リポジトリ外の状態）に書き込まれる
- **存在しない dir は無視される**: `fish_add_path` は `test -d` で弾くので、マシンによって入っていないツール（pulumi 等）の行を残しても PATH は汚れない。裏返すと、シェル起動後に初めて作られた dir（初回 `go install` 前の `~/go/bin` など）は新しいシェルを開くまで PATH に入らない
- **Home Manager の `home.sessionPath` は使わない**: `hm-session-vars.sh` に出力される `export PATH="…:$PATH"` は無条件の prepend で、config.fish 冒頭が入れ子のたびに source し直す（`set -e __HM_SESS_VARS_SOURCED`）ため冪等にできない。cargo はかつて `nix/modules/rust-tools.nix` の `home.sessionPath` と config.fish の二重宣言だったが、config.fish に一本化した（#595）

### PATH の優先順位

原則は「**Nix 版が常に勝つ**」です（#596）。PATH は次の 3 層の順に並び、同名のコマンドがあれば上の層が勝ちます。

| 順 | 層 | PATH 上の位置 | 入れるもの | 役割 |
|----|----|---------------|------------|------|
| 1 | mise installs（`~/.local/share/mise/installs/*`） | 先頭 | mise の hook-env（プロンプトのたび） | `.mise.toml` で指定したバージョンを、そのディレクトリの中でだけ最優先で効かせる |
| 2 | Nix（`~/.nix-profile/bin`） | 中間（`/usr/bin` より前） | ログイン時の Nix プロファイルスクリプト | Home Manager で宣言したものは「あれば必ず勝つ」 |
| 3 | `~/.cargo/bin`、`~/.local/bin` | 末尾（`/usr/bin` より後ろ） | config.fish の `string match -v` で既存エントリを除去してから `fish_add_path --path --append` | Nix に無いもの（`~/.cargo/bin`: deno / zellij / broot 等 cargo install 専用ツール、`~/.local/bin`: claude 等の native installer、手動ビルド）だけを拾うフォールバック |

**なぜ `~/.local/bin` を末尾に置くのか。** `~/.local/bin` は curl installer や native installer が勝手に書き込む場所で、ツールの管理層を Nix へ移した後も旧版が残りやすい。先頭側にあった頃は、残った旧版（化石）が PATH の先勝ちで Nix 版を黙って隠す事故が実際に起きた（#584 の mise、それ以前の claude の npm 版）。末尾に置けば、Nix にあるものを `~/.local/bin` が隠す経路そのものが無くなる。

代償として、次の 2 つは成立しません。どちらも意図した制約です。

- **native installer で Nix 版を上書きできない**: Nix 版が壊れたときの一時退避として `~/.local/bin` に別版を置いても、Nix 版が勝つ。上書きしたいときは Nix 側を直すか、フルパスで呼ぶ
- **OS パッケージとも同名にできない**: `/usr/bin` 等より後ろなので、pacman で入っているものと同名のファイルを `~/.local/bin` に置いても効かない。効かないと思ったら `type -a <名前>` で前にある同名を確認する

**なぜ mise installs は先頭のままでよいのか。** mise は `.mise.toml` を置いたディレクトリでだけ効く、明示的な上書きの仕組みです。化石のように「知らないうちに残る」ものではなく、指定した本人の意図が勝つべき層なので Nix より前に置く。hook-env がプロンプトのたびに先頭へ入れ直すため、config.fish の行の順序にも左右されません。

- **`~/.cargo/bin` は #611 で `~/.local/bin` と同じ末尾フォールバックに揃えた**: Nix へ移す前に `cargo install` していた bat / fd / rg / starship など 18 個が `~/.cargo/bin` に残っていて、Nix より前に並んでいた頃は #584 と同じ形で Nix 版を隠していた。末尾に回したことで解決先が Nix 版へ変わる（skim 0.16 → 5.0 などメジャー更新を含む）ので、`switch` 後は `type -a <名前>` で確認するとよい。Nix と同名の cargo 版そのものの掃除（`cargo uninstall`）は各マシンでの手作業として別途行う（[install-unmanaged-tools.md](../how-to/install-unmanaged-tools.md) 参照）
- **`~/.pyenv/bin` は今回の原則の適用外**: Nix より前に並ぶが、中身は `pyenv` 1 個で Nix と同名の衝突は無い
- **rustup proxy がある環境の注意**: `~/.cargo/bin` に `cargo` / `rustc` / `rustup` の rustup proxy がある環境（rustup を公式 installer で入れた機など）では、`--append` 後は `cargo` 自体の解決先も Nix 版（または `/usr/bin`）に変わる。`type -a cargo` で確認すること
- **`--append` だけでは既にある dir を動かさない。`string match -v` で先に取り除いてから append する**: `fish_add_path --path --append` は PATH に既にある dir には何もしないので、switch 前の古い PATH(`~/.cargo/bin` や `~/.local/bin` が先頭側)を受け継いだシェルでは位置が変わらず、herdr のような常駐プロセスから生える新しい fish が switch 後もその旧位置を引き継いでしまう(#611 のレビューで指摘)。当初はこれを `fish_add_path --move` で直していたが、`--move` は PATH に同じ dir が複数回入っていても**最初の1個しか末尾へ移さず**、残りの重複はその場に残ってしまう(#617)。長寿命プロセス(herdr デーモン等)由来の env はまさにこの「重複あり」の形で古い PATH を蓄積しているため、`--move` では取りこぼしが発生する。`set -gx PATH (string match -v -- $HOME/.cargo/bin $PATH)` で既存エントリを**重複ごと全部**取り除いてから `fish_add_path --path --append` するので、入れ子シェルでも、重複があっても、PATH の順序は正しく直る
- **ただし PATH の順序が直っても、新しいターミナルからの再起動は依然として推奨**: この `string match -v` + `--append` が直すのは PATH の順序だけで、`home.sessionVariables` に新しく追加された変数など、config.fish の実行だけでは反映されない環境変数もある。確実に反映させたいときは、既存の fish の中からではなく新しいターミナルから fish を起動し直す

---

## 🤔 Why This Architecture

### 従来の問題点

以前の構成では以下の問題がありました：

1. **デッドコード**: `.bash_profile` 内のコードが `exec fish` 後に実行されない
2. **重複設定**: 同じ設定が `.bashrc` と `config.fish` の両方に存在
3. **無意味な alias**: Bash の alias は `exec` で引き継がれない

```bash
# 旧 .bashrc（問題あり）
alias vim='nvim'      # ← exec fish で消える（無意味）
alias rm='rm -i'      # ← 同上
export TERM=xterm-256color
exec fish
. "$HOME/.cargo/env"  # ← 実行されない（デッドコード）
```

### 現在の設計原則

1. **Single Source of Truth**: 各設定は1箇所のみで定義
2. **Clear Responsibilities**: Bash は起動のみ、設定は Fish で
3. **No Dead Code**: 実行されないコードは削除
4. **POSIX Compatibility**: ログインシェルは Bash のまま

### 設定の配置ガイド

| 設定の種類 | 配置場所 | 理由 |
|-----------|---------|------|
| 環境変数（POSIX ツール用） | `.bashrc` | `exec` 前に設定、Fish に引き継がれる |
| 環境変数（一般） | `config.fish` | Fish で管理 |
| PATH 設定 | `config.fish` | Fish で管理 |
| エイリアス | `config.fish` | alias はプロセス間で引き継がれない |
| プロンプト | `config.fish` | Fish 専用 |
| ssh-agent | `.bashrc` | `exec` 前に起動、環境変数が引き継がれる |

---

## 🔗 Related Documentation

- [keybindings.md](../reference/keybindings.md) - Fish/Tmux/Hyprland のキーバインド
- [architecture.md](./architecture.md) - 全体のアーキテクチャ設計
- [install-and-update-packages.md](../how-to/install-and-update-packages.md) - Nix/Home Manager でのパッケージ管理

---

**この構成により、POSIX 互換性と Fish の快適さを両立しています。** 🐟
