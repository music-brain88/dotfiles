# mise Tasks / mise タスク一覧

> **Diátaxis:** 📖 Reference

このリポジトリでは、よく使うコマンドを [mise](https://mise.jdx.dev/) タスクとして `.mise.toml` に定義しています。長いコマンドを覚える必要がなく、`mise run <task>` で簡単に実行できます。

```bash
# タスク一覧を表示
mise tasks
```

---

## Nix Tasks

| Task | Description | Equivalent Command |
|------|-------------|---------------------|
| `mise run nix:build` | Home Manager 設定をビルド (profile 自動判別) | `nix build .#homeConfigurations.<profile>.activationPackage` |
| `mise run nix:switch` | ビルド＆アクティベート (profile 自動判別) | build + `./result/activate` |
| `mise run nix:check` | Flake チェック実行 | `nix flake check` |
| `mise run nix:update` | Flake inputs を更新 | `nix flake update` |
| `mise run nix:gc` | 古い世代をガベージコレクト | `nix-collect-garbage -d` |

`nix:check` は、flake の `checks` 出力もビルドして実行する。いまの検査は、herdr の Claude Code 用フックを呼ぶ hooks のエントリが、herdr のインストーラの生成物とずれていないかを見る `checks.herdr-claude-hook-entries` である。CI の `check` ジョブは `nix flake check --no-build` なのでこの検査を実行しないが、`verify-docker` ジョブが同じ検査をビルドして実行する。手元でこのタスクを実行すると、PR を出す前にずれに気づける（[nix-modules.md の「Claude Code の pane の復元」](./nix-modules.md#claude-code-の-pane-の復元)、[#755](https://github.com/music-brain88/dotfiles/issues/755)）。

`nix:build` と `nix:switch` は、profile を `uname -r` から自動判別する。WSL カーネル (`microsoft` を含む) なら `archie-wsl` を使い、それ以外なら `archie` を使う。そのため、両マシンで実行するコマンドは同一である。

次の表は、mise タスクではないが、あわせてよく使うNix関連コマンドを並べたものである。

| Command | Description |
|---------|-------------|
| `nix develop` | Nixツール入りの開発シェルに入る（nil, nixpkgs-fmt, nix-tree） |

---

## Lint Tasks

| Task | Description | Equivalent Command |
|------|-------------|---------------------|
| `mise run lint:shellcheck` | 追跡済みの `*.sh` をすべて shellcheck にかける。版は `flake.lock` の nixpkgs が固定する版で、CI の `check` ジョブと同じ版・同じ対象になる | `nix run .#shellcheck` |

shellcheck の定義の正は `flake.nix` の `apps.${system}.shellcheck` である。CI の `check` ジョブも同じ app を呼ぶので、手元で通れば CI でも通る。mise が無い環境では、等価コマンドの `nix run .#shellcheck` を直接実行する。シェルの PATH の `shellcheck` は版が異なりうるので、CI と揃えたいときは使わない（[#665](https://github.com/music-brain88/dotfiles/issues/665)）。

---

## Claude Code Tasks

| Task | Description | Equivalent Command |
|------|-------------|---------------------|
| `mise run claude:effort <level>` | Claude Code の effort 設定(effortLevel/ultracode)を更新してNix経由で反映 (`low` / `medium` / `high` / `xhigh` / `ultracode`) | `.config/claude/settings.json` を jq で書き換え + `nix:switch` |
| `mise run claude:wtclose-test` | 締め skill `wtclose` の検問スクリプトのテストを、一時ディレクトリの fixture と偽の `gh` だけで実行する(実物の vault には触らない) | `bash .config/claude/skills/wtclose/tests/close_gate_test.sh` |
| `mise run claude:wtclean-test` | 掃除 skill `wtclean` の収穫ステップの検索スクリプトのテストを、一時ディレクトリのノートと偽の `gh` だけで実行する(実物の vault は読まない) | `bash .config/claude/skills/wtclean/tests/harvest_search_test.sh` |

`ultracode` は effortLevel の値ではなく、独立した boolean 設定キーである。xhigh 相当の effort に加えて、常設の dynamic-workflow(マルチエージェント)オーケストレーションをセッション全体で有効にする。`mise run claude:effort ultracode` を実行すると `effortLevel = "xhigh"` と `ultracode = true` が書き込まれる。通常レベル(low/medium/high/xhigh)に戻すと `ultracode` キー自体を削除し、設定ファイルを最小に保つ。

次の表は、mise タスクではないが、あわせて使うグローバルタスクを並べたものである。グローバルタスクは `.config/mise/config.toml` で定義されていて、リポジトリを問わずどのディレクトリからでも実行できる。

| Task | Description |
|------|-------------|
| `mise run claude:memory-wire [project]` | プロジェクトの auto-memory を Obsidian AgentMemory vault へ配線 (`.claude/settings.local.json` に `autoMemoryDirectory` を書き込む、端末ローカル・untracked)。git repo の外では cwd を root として扱う。`$HOME` と `/` では止まる。配線していない場所で起動したセッションの記憶は、ユーザー設定(`.config/claude/settings.json` の `autoMemoryDirectory`)の既定フォルダ `AgentMemory/home` へ行く |

---

## Memory Tasks

| Task | Description | Equivalent Command |
|------|-------------|---------------------|
| `mise run memory:index` | AgentMemory の各プロジェクトについて、記憶ファイルの frontmatter から枝の索引(`index/project.md`・`index/reference.md`)と root `MEMORY.md` のマーカー区間を生成する。`--project` を付けない全体実行では、vault のセッションノート(`Zettelkasten/ResearchNotes/ClaudeCodeSession-*.md`)から `sessions/INDEX.md` と月別の `sessions/YYYY-MM.md` を、私記(`episodes/*.md`)から `episodes/INDEX.md` も生成する。既定では実物の vault(`~/Documents/Obsidian/AgentMemory`)に書く | `python3 -I .config/claude/scripts/build_memory_index.py` |
| `mise run memory:index-check` | 各プロジェクトの root `MEMORY.md` の行数とバイト数を、上限(200 行 / 25,000 バイト)と目標(100 行 / 15,000 バイト)に並べて表にする。上限を超えた root があれば終了コード 1 を返す。全体実行では `sessions/INDEX.md`・`sessions/YYYY-MM.md`・`episodes/INDEX.md` の行数とバイト数も並べる(これらは必要なときに開くファイルなので上限と目標の列は `-` で、終了コードに影響しない)。何も書かない | `python3 -I .config/claude/scripts/build_memory_index.py --check` |
| `mise run memory:index-test` | 索引ビルダーのテストを、一時ディレクトリの fixture だけで実行する(実物の vault には触らない) | `python3 -I -B -m unittest discover -s .config/claude/scripts/tests -p '*_test.py' -v` |

`memory:index` と `memory:index-check` には、スクリプトの引数をそのまま続けて渡せる。`--root <path>` は AgentMemory のルートを変え、`--vault <path>` はセッションノートを探す vault のルートを変え(既定は `--root` の親ディレクトリ)、`--project <name>` は対象を 1 プロジェクトに絞る(`--project` を付けると sessions と episodes の索引は作らない)。vault のコピーで試すときは、コピーの中の AgentMemory と `Zettelkasten/ResearchNotes` を実物と同じ相対配置に置き、`mise run memory:index --root <コピーのパス>/AgentMemory` のように実行する。セッションノートの置き場が無いとき、スクリプトは sessions の索引を 1 行の通知だけ出して飛ばす。

セッションの索引は vault 共通の月別で、`sessions/INDEX.md` に月ごと 1 行(本数・月内で多い順の上位 tags 3 つ・⏳ の本数)、`sessions/YYYY-MM.md` に 1 ノート 1 行(日付・wikilink・最初の H1 の文・tags・⏳)が載る。⏳ は `triage: candidate` のまま `distilled_to` が空(キー無し・空文字・`[]`)のノートに付く。`episodes/INDEX.md` には私記が 1 本 1 行(日付・`name`・`description`・`origin_session`)で日付順に載る。どのファイルも先頭に `type: index` の frontmatter が付く。書き先に先頭がこの frontmatter でない手書きのファイルがあると、スクリプトはどのファイルも書かずに終了コード 2 で止まる。中身が無くなった月のファイルと `episodes/INDEX.md` は、スクリプトの生成物のときだけ消える([#729](https://github.com/music-brain88/dotfiles/issues/729))。

スクリプトが root `MEMORY.md` で書き換えるのは、`<!-- memory-index:begin -->` と `<!-- memory-index:end -->` の間だけである。マーカーの外は手書き領域として残る。ただし、手書き領域の箇条書きの行が同じプロジェクトの記憶ファイルを指していて、その記憶が今回の生成に載った場合は、スクリプトがその行を取り除き、stdout に `removed:` の行として出力する。マーカーの無い root に初めて実行すると、スクリプトはファイル全体を手書き領域とみなし、末尾にマーカー区間を足す。マーカーが片方しか無いなど壊れた root が 1 つでもあると、スクリプトはどのファイルも書かずに終了コード 2 で止まる([#720](https://github.com/music-brain88/dotfiles/issues/720))。

---

## Docker Tasks

| Task | Description | Equivalent Command |
|------|-------------|---------------------|
| `mise run docker:build` | Docker イメージをビルド | `docker build -t arch .` |
| `mise run docker:run` | コンテナを起動（16GB mem, 4096 CPU shares） | `docker run -itd --cpu-shares=4096 -m 16G --name arch arch:latest` |
| `mise run docker:start` | 停止中のコンテナを起動 | `docker start arch` |
| `mise run docker:stop` | コンテナを停止 | `docker stop arch` |
| `mise run docker:exec` | コンテナ内で bash 実行 | `docker exec -it arch bash` |
| `mise run docker:remove` | コンテナを停止＆削除 | `docker stop arch && docker rm arch` |

---

## Neovim Tasks

| Task | Description | Equivalent Command |
|------|-------------|---------------------|
| `mise run nvim:ts-install` | `treesitter_parsers.lua` のリストに従い nvim-treesitter のパーサをインストール(冪等) | headless nvim 経由で `ts.install()` |
| `mise run nvim:state` | dpp state(`startup.vim`/`state.vim`)を headless で強制再生成(`check_files()` の差分有無を問わない)。pull後・`nix:switch` 後の明示反映用([#466](https://github.com/music-brain88/dotfiles/issues/466)) | headless nvim 経由で `dpp#make_state()` |

プラグインのインストールは mise タスクにしていない。初回起動時に `init.lua` が未取得を検知して自動インストールし、手動で入れ直すときは Neovim 内で `:DppInstall` を実行する。自動インストールの仕組みと、state 鮮度管理の4経路(BufWritePost / 起動時 check_files / `:DppMakeState` / `mise run nvim:state`)の使い分けは [neovim-config.md](neovim-config.md#-plugin-management-dpp) に書いてある。

---

## Utility Tasks

| Task | Description | Equivalent Command |
|------|-------------|---------------------|
| `mise run backup` | Arch Linux パッケージリストをバックアップ (`.backup/` は gitignore 対象・ローカル用) | `mkdir -p .backup/pacman && sudo pacman -Qne > .backup/pacman/pkglist.txt` |

---

## GPG Tasks

GPG タスクは、署名鍵を複数端末で運用するためのタスクである。手順の詳細は [manage-gpg-keys.md](../how-to/manage-gpg-keys.md) に書いてある。

| Task | Description |
|------|-------------|
| `mise run gpg:status` | 署名鍵の有効期限を表示し、期限が近いと警告 |
| `mise run gpg:export` | 転送バンドル(公開鍵 + 秘密サブキー + ownertrust)を `.backup/gpg/` に生成 |
| `mise run gpg:import` | 新端末でバンドルをimportし、trust設定まで完了(バンドルが無ければBitwardenから自動取得) |
| `mise run gpg:extend` | 期限延長(主キー +5y、サブキー +2y)+ バンドル再生成 |
| `mise run gpg:bw:push` | バンドルをBitwardenアイテム(既定: `gpg-bundle`)の添付としてアップロード |

---

## SOPS age Tasks

SOPS age タスクは、hexhive の Secrets(SOPS + age)で使う鍵を管理する。秘密鍵の正本は Bitwarden に置く。ローカルの置き場は `~/.config/sops/age/keys.txt`(sops が自動参照するパス)である。方式は GPG タスクと同じ「Bitwarden 添付 + fetch-if-absent」である。

| Task | Description |
|------|-------------|
| `mise run age:keygen` | age 鍵ペアを新規生成(既存鍵があれば拒否)+ 公開鍵を表示 |
| `mise run age:status` | ローカル鍵から公開鍵を表示(`.sops.yaml` 更新用) |
| `mise run age:import` | 新端末で Bitwarden から鍵を復元(ローカルにあれば何もしない) |
| `mise run age:bw:push` | 鍵を Bitwarden アイテム(既定: `sops-age-key`)の添付としてアップロード |

---

## Hyprland Tasks

| Task | Description | Equivalent Command |
|------|-------------|---------------------|
| `mise run hypr:pm-update` | Hyprland アップグレード後に hyprpm 管理プラグインを再ビルド(Nix ではなく Arch のツールチェーンを強制)。`hyprpm` は `hyprland` とは別の pacman パッケージ(`extra/hyprpm`)なので、事前に `sudo pacman -S hyprpm` で導入しておく(無ければタスクが案内して止まる) | `PATH="/usr/bin:$PATH" hyprpm update` |

Nix プロファイルの cmake は純粋性パッチにより `/usr` を探索できず、システムの OpenGL/GLES3 が見つからずビルドに失敗する([#554](https://github.com/music-brain88/dotfiles/issues/554))。同じ理由で Nix の pkg-config は AUR のビルドも壊すため、[#740](https://github.com/music-brain88/dotfiles/issues/740) で Nix から外した。`/usr/bin` を先頭に置いて Arch のツールチェーンを強制する。sudo プロンプトが出るため対話ターミナルで実行すること。

---

## Usage Examples

次の例は、よく使うタスクの組み合わせを示す。

```bash
# 設定を更新してアクティベート
mise run nix:switch

# パッケージを最新に更新
mise run nix:update
mise run nix:switch

# ディスク容量を解放
mise run nix:gc
```

```bash
# Dockerで動作確認
mise run docker:build
mise run docker:run
mise run docker:exec
```

---

## 🔗 Related Documentation

- [getting-started.md](../tutorials/getting-started.md) - 初回セットアップ
- [install-and-update-packages.md](../how-to/install-and-update-packages.md) - パッケージの追加・更新・ロールバック
- [nix-modules.md](./nix-modules.md) - Nixモジュール構成
