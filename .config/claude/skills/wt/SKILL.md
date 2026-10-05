---
name: wt
description: "タスクの説明からブランチ名を自動生成し、herdr の worktree + workspace を立ち上げ、必要なら作業担当エージェントに委任する。ユーザーが新しい作業を始めたい・worktree を切りたい・「/wt」と言った時に使う。"
---

# Worktree 作成 (herdr)

## Overview

タスクの説明からブランチ名を自動生成し、herdr の worktree + workspace を立ち上げます。

司令塔はセッションを締めるときに `wtclose` を呼ぶ。締めの条件は、`wtclose` の Stop hook が呼ぶ検問スクリプトが確かめる(#658)。

## Parameters

- **タスク説明**(必須): ユーザーが `/wt` に続けて入力する自然文。ブランチ名の生成、worktree/workspace の作成、および該当する場合はエージェントへの作業指示プロンプト作成の入力になる(実体は末尾の [引数](#引数) セクション参照)

## Steps

### 1. リポジトリの確認

**Constraints:**
- **MUST**: `git rev-parse --show-toplevel` でリポジトリルートを確認する
- **MUST**: git リポジトリでない場合は中断してユーザーに知らせる

### 2. ブランチ名の生成

ユーザーの入力からブランチ名を生成する。

**Constraints:**
- **MUST**: conventional commit message のような形式で生成する(`feat/` `fix/` `chore/` `ci/` `docs/` などの type を prefix にする)
- **SHOULD**: prefix 以降は英語の snake_case で、単語 2〜4 個を目安に簡潔に
- **SHOULD**: 迷ったら `feat/` か `fix/` に寄せる
- **MUST**: 生成したブランチ名が既存ブランチと重複していないか `git branch --list <name>` で確認する
- **MUST**: 重複する場合は接尾辞を変えて再生成する

### 3. worktree + workspace の作成

#### 司令塔の自己命名

worktree を作成する前に、司令塔自身に安定した名前を付ける。作業者からの上り報告(手順5「(3) 上り=内容」参照)の push 先として使うため。

```bash
herdr agent rename "$HERDR_PANE_ID" "commander-$(basename "$(git rev-parse --show-toplevel)")"
```

**Constraints:**
- **MUST**: `$HERDR_PANE_ID` は herdr が各ペインのシェルに注入する環境変数で、司令塔自身の pane を自己識別する(実機確認済み)
- **MUST**: 名前は `commander-<repo名>`(`git rev-parse --show-toplevel` の basename)とする。複数リポジトリで司令塔が並行稼働しても衝突しない
- **MUST**: 毎回再宣言を試みる。ただし rename は herdr デーモン再起動・セッション終了を跨いで pane に名前が残るため、過去セッションの pane が同名を保持していると単純な再宣言では冪等にならない(実例3件: #427)
- **MUST**: rename が `agent_name_taken` で失敗した場合、サフィックス付きの名前で空いているものまで採って再試行する。デフォルトは数字サフィックス(`commander-<repo名>-2`, `-3`...)。タスク由来の意味サフィックス(例: `commander-dotfiles-dpp`)も可 — 同一リポジトリで複数司令塔が同時稼働している場合、どの司令塔か人間が識別しやすくなる。要件はユニークであることのみ
- **MUST**: サフィックス付き名を採用した場合、以降そのセッションで使う「作業指示プロンプト」内の司令塔宛先(手順4テンプレートの `commander-<repo名>` 箇所すべて。【相談】【報告】の push 2箇所と、「## 相談」の無応答フォールバックの `herdr agent get` の計3箇所)を実際に採用した名前に統一する
- **MUST NOT**: `herdr agent rename` は司令塔が自分自身(`$HERDR_PANE_ID`)に対してのみ実行する。作業者や他ペインの名前を司令塔側から書き換えない

```bash
herdr worktree create --cwd <repo-root> --branch <branch-name> --base main --focus
```

**Constraints:**
- **MUST**: worktree 作成前に `git fetch origin && git merge --ff-only origin/main` でローカル main を最新化する(特にマージ直後に続けて次の worktree を切る連続運用で必須。詳細: `/wtclean` Troubleshooting「git branch -d の not yet merged to HEAD 警告」参照)
- **MUST**: ベースブランチはデフォルト `main`。ユーザーが入力内で別のベースを指定した場合はそれに従う
- **MUST**: 作成結果(worktree のパス、workspace ID)をユーザーに報告する
- **MUST**: 応答 JSON の `result.root_pane.pane_id`(worktree 専用 workspace のルート pane)を控えておく。手順4でエージェント用 pane を割る際の split 元として使う

#### worktree の準備

worktree 作成直後に以下を行う:

**Constraints:**
- **MUST**: `mise trust <worktree-path>` を実行する(詳細: Troubleshooting「mise trust 忘れ」参照)
- **MUST**: allowlist を配置する: `mkdir -p <worktree-path>/.claude && cp ~/.claude/templates/wt-settings.local.json <worktree-path>/.claude/settings.local.json`
  - コピー元は `<repo-root>/.config/claude/templates/...` ではなく `~/.claude/templates/...` を使う。`<repo-root>` は `/wt` を呼び出した対象リポジトリ次第で変わり、dotfiles 以外のリポジトリではこのテンプレートを含まないため
  - `~/.claude` への反映は home-manager 経由(`home.nix` の `home.file ".claude".source = ./.config/claude`)で、`mise run nix:switch` 実行時に `/nix/store` スナップショットへの per-file symlink が生成される方式。テンプレートを追加・変更したら `mise run nix:switch` を実行しないと `~/.claude/templates/` に反映されない(詳細: Troubleshooting「allowlist テンプレートの cp 失敗」参照)
  - 定型で安全な操作(`git`・`gh`・`mise`・`herdr` の一部サブコマンド、司令塔がタスク指示を置く作業記憶 `~/Documents/Obsidian/AgentMemory/workbench/` の読み書き、vault が無い機械でタスク指示を置くスクラッチパッドの読み取り)を宣言的に許可し、作業者の permission 往復(A類)を設計で消す。詳細は allowlist テンプレート本体を参照

### 4. エージェントの起動(任意)

タスク内容が具体的な場合、新しい workspace でエージェントを起動してタスクを渡す。

#### 指示書の材料集め(Explore)のモデル

作業指示プロンプトの「## 背景」に載せる事実(関連ファイル・行番号・既存の契約・テスト基盤)を Explore サブエージェントに集めさせる場合の指針:

**Constraints:**
- **SHOULD**: Explore の `model` は `opus` を既定にする。実装制約(置き場・鍵の材料・テスト基盤の `cfg(test)` 制約・docs のドリフト)まで洗い出したいときだけ `fable` にする(所要とトークンは 2〜3 倍、md ファイルの行番号がずれる癖がある。ズレ幅はまちまちで、2026-09-27 の比較では 5 件中 4 件が 1〜3 行、1 件は 9 行だった)
- **SHOULD**: 報告の長さは「5,000 字程度」のような目安ではなく、数えられる制約(引用 N 本まで・1 節 M 行まで)で書く(2026-09-27 の比較では 3 モデルとも目安を守らなかった)
- **MUST**: Explore の報告の行番号は司令塔が `sed -n` / `grep -n` で標本検査してから指示書に写す(モデルに依らず md の行番号はずれうる)

#### GPG パスフレーズキャッシュの事前チェック

worker はコミット時に GPG 署名で詰まりやすい(worker pane は tty を持たず pinentry を表示できない構造的制約。詳細: Troubleshooting「GPG 署名コミットは worker pane から pinentry を出せない」参照)。委任前にキャッシュの有無を確認し、冷えていれば温めておく。

```bash
KEYID=$(git config user.signingkey)
[ -n "$KEYID" ] || { echo "git config user.signingkey is not set" >&2; exit 1; }
KEYGRIP=$(gpg --list-secret-keys --with-keygrip "$KEYID" 2>/dev/null \
  | awk '/^ssb/ && /\[S\]/ {found=1; next} found && /Keygrip/ {gsub(/ /,"",$0); sub(/Keygrip=/,""); print; exit}')
[ -n "$KEYGRIP" ] || { echo "No [S] subkey keygrip found for $KEYID — cannot identify the signing key" >&2; exit 1; }
gpg-connect-agent 'keyinfo --list' /bye | grep "$KEYGRIP" | awk '{print $7}'  # 1 = cached
```

**Constraints:**
- **MUST**: 署名鍵の keygrip は次の手順で特定する: `git config user.signingkey` で鍵IDを取得し、`gpg --list-secret-keys --with-keygrip` の出力から同じ鍵に属する `[S]` フラグ付きサブキー(ssb)行の直後にある `Keygrip` を読む(`user.signingkey` は primary 鍵の ID を指すが、実際の署名には `[S]` サブキーの keygrip が使われるため。実機確認済み)
- **MUST**: 上記 keygrip で `gpg-connect-agent 'keyinfo --list' /bye` の出力(`S KEYINFO <keygrip> D - - <cached> P - - -` 形式)をフィルタし、7列目が `1` かどうかでキャッシュの有無を確認する(実機確認済み)
- **MUST**: `KEYID`(`user.signingkey` 未設定)または `KEYGRIP`([S] サブキーが無い鍵構成)が空なら、agent に問い合わせる前に失敗させ「署名鍵を特定できない」と報告する(上記ワンライナーの `[ -n ... ] ||` ガード。`.mise.toml` の `gpg:*` タスクと同じ流儀)。空文字で `grep "$KEYGRIP"` すると全 KEYINFO 行にマッチし、無関係な鍵の cached フラグを署名鍵のものと誤読しうるため(PR #625 のレビュー指摘)
- **SHOULD**: 冷えている(7列目が `1` でない)場合、ユーザーに1回署名(`echo test | gpg --clearsign -o /dev/null`)によるキャッシュ温めを依頼する
- **MAY**: 温めは委任と並行に進めてよいが、worker がコミットに到達する前に温まっているのが望ましい

#### 作業物の置き場(作業記憶)

司令塔は、指示書・判定表・報告・供養ログを、vault の作業記憶 `AgentMemory/workbench/<project>/` に置く(#658)。これらはセッションとマシンを跨いで読まれるため、セッションが終わると消えるスクラッチパッドには置かない。`herdr agent wait` の待ち受けログは、そのセッションの中だけで使うので、スクラッチパッドに残す(手順5(2) 参照)。

作業記憶の場所は、締めの検問スクリプトが求める。検問と同じ求め方(記憶の配線 `autoMemoryDirectory` を先に見る)を使うため、司令塔は自分で組み立てない:

```bash
wb="$(bash ~/.claude/skills/wtclose/close_gate.sh --where workbench_dir)" && mkdir -p "$wb"
```

作業記憶に置く md は、先頭に次の frontmatter を持つ:

```yaml
---
type: agent-workbench
kind: brief
unit: <branch-name>
created: <YYYY-MM-DD>
---
```

**Constraints:**
- **MUST**: `kind` は `brief`(指示書)・`verdict`(判定表)・`report`(報告)・`memorial`(供養ログ)・`handoff`(HANDOFF.md の写し)のどれかにする。`index` は検問が書く一覧の専用で、司令塔は使わない
- **MUST**: `unit` は、作業物が属する作業のブランチ名にする(指示書を書く時点では PR 番号がまだ無いため)。PR 番号で書く場合は `"#663"` のように引用符で囲む(囲まないと YAML が `#` から後ろをコメントとして読む)
- **SHOULD**: 1 つの記憶に複数のリポジトリを束ねている場合は、`unit` にリポジトリの修飾子を付ける(`"owner/repo#663"`、`"owner/repo@feat/x"`)。修飾子を省いた `unit` は、検問が走っているリポジトリの単位として読まれる
- **MUST**: ファイル名は `<YYYYMMDD>-<kind>-<ブランチ名の / と _ を - に置き換えたもの>.md` にする(例: `20261004-brief-feat-wtclose-close-gate.md`)。同じ日に同じ組み合わせがもう 1 つ要るときは `-2` を付ける
- **MUST NOT**: 作った後で別のフォルダへ移さない。メモリや起動プロンプトが絶対パスで参照する
- **MUST**: 次のセッションでも読む作業物は、状態ファイル・セッションノート・メモリのどれかからリンクする。どこからも辿れなくなって 14 日を過ぎた作業物は、締めの検問が忘れる候補として一覧に出す(消すのはユーザーの OK の後)
- **MUST**: `--where` が失敗する環境(vault が無い機械)では、従来どおり司令塔自身のスクラッチパッドディレクトリに置く

#### pane の用意とエージェント起動

司令塔は、pane の用意とエージェント起動を分けて行う。エージェント起動はさらに、起動プロンプトを付けない `herdr agent start`(1 段目)と、名前宛ての `herdr agent prompt` による起動プロンプトの送達(2 段目)に分ける。herdr 0.9.1 では、起動プロンプトを引数に付けた `agent start` がタイムアウトし、worker に名前が付かないため(詳細: Troubleshooting「起動プロンプト付きの agent start が 0.9.1 でタイムアウトし worker に名前が付かない」参照)。まず worktree 専用 workspace のルート pane(手順3で控えた `result.root_pane.pane_id`)から下に pane を割り、作業指示は作業記憶(上記「作業物の置き場」参照)にファイルとして書く(長文プロンプトを直接 inline できない理由は下記 Constraints 参照):

```bash
herdr pane split --pane <root-pane-id> --direction down --cwd <worktree-path>
```

新しい pane-id は応答 JSON の `result.pane.pane_id` から取得する。続けて作業指示をファイルに書き、起動プロンプトを付けずにエージェントを起動する(1 段目):

```bash
cat > "$wb/<YYYYMMDD>-brief-<branch-slug>.md" <<'PROMPT'
---
type: agent-workbench
kind: brief
unit: <branch-name>
created: <YYYY-MM-DD>
---

<作業指示プロンプト（複数行可）>
PROMPT

herdr agent start claude-<branch-name 由来のユニーク名> --kind claude --pane <new-pane-id> -- --model <model> --effort <effort> --permission-mode auto
```

1 段目が成功すると、`agent start` は終了コード 0 を返し、結果 JSON の `result.agent` に付けた名前(`name`)・`"agent_status":"idle"`・`"interactive_ready":true` が入る(2026-10-05 の実測では約 4.0 秒で戻った)。司令塔は、これと `herdr agent get <名前>` の成功で名前が登録されたことを確かめてから、起動プロンプトを名前宛ての `agent prompt` で渡す(2 段目):

```bash
herdr agent get claude-<branch-name 由来のユニーク名>

herdr agent prompt claude-<branch-name 由来のユニーク名> "<作業記憶のディレクトリ>/<YYYYMMDD>-brief-<branch-slug>.md をあなた自身が読み(サブエージェントに委任しない)、その内容全体をあなたへの作業指示として忠実に実行してください。" --wait --until working --until blocked
```

2 段目の後、司令塔は手順5(1)の標準手順で `working` への遷移を確かめる。`herdr agent get <名前>` で `working` を確かめ、遷移していなければ `herdr agent read` でメニューが出ていないことを確かめたうえで `herdr pane send-keys <pane-id> Enter` で追撃する(詳細: 手順5「(1) 下り=指示」の Constraints 参照)。`working` を確かめたら、手順5(2)の `herdr agent wait` を仕掛ける。

**Constraints:**
- **MUST**: pane の用意は `herdr pane split` で行う。split 元の `--pane` には手順3の `result.root_pane.pane_id`(worktree 専用 workspace のルート pane)を使う。司令塔自身の pane(`$HERDR_PANE_ID`)を split 元にすると、worker pane が司令塔の workspace 側に作られてしまい、worker を worktree 専用 workspace に置く設計(旧構文の `--workspace` 指定が担っていた部分)が壊れる
- **MUST**: `--cwd` は必須。省略すると split 元 pane の cwd を引き継ぎ、worktree 外で作業が始まってしまう
- **MUST**: `pane split` の `--direction down` で pane を上下分割にする(省略時はデフォルトの `right` で左右分割になってしまう)
- **MUST**: pane split 直後に `herdr agent start` を投げない。split 直後は pane 内のシェルがまだ使える状態になっておらず、`agent_pane_busy`(`agent target pane <pane-id> is not an available shell`)で拒否されうる。`herdr pane process-info --pane <new-pane-id>` の `result.process_info.foreground_processes[].name` で前面プロセスがシェルになったことを確認してから起動し、確認できなければ数秒待って再試行する(詳細: Troubleshooting「pane split 直後の agent start が agent_pane_busy で拒否される」参照)
- **MUST NOT**: `herdr agent start` に `--workspace` / `--cwd` / `--split` / `--focus` を渡さない。herdr 0.7.5 で廃止され `unknown option` エラーになる。pane はあらかじめ `pane split` で用意し、`agent start` には `--pane <pane split で得た pane-id>` を渡す
- **MUST**: `--kind claude` が実行ファイルの正典を与えるため、`--` 以降には実行ファイル名(`claude`)を含めず、引数のみを渡す
- **MUST NOT**: `agent start` の `--` 以降に起動プロンプトを付けない。herdr 0.9.1 では、起動プロンプト付きの `agent start` は worker を起動するものの、約 30 秒(既定の `--timeout 30000`)後に `timeout` エラーと終了コード 1 を返し、worker に名前が付かない(2026-10-05 に 5 体中 5 体で再現。詳細: Troubleshooting「起動プロンプト付きの agent start が 0.9.1 でタイムアウトし worker に名前が付かない」参照)
- **MUST**: 2 段目に進む前に、1 段目の終了コードが 0 であること、結果 JSON の `result.agent.name` が付けた名前で `result.agent.interactive_ready` が `true` であること、`herdr agent get <名前>` が成功することを確かめる。1 段目が `timeout` を返した場合や、`agent get` が `agent_not_found` を返した場合は、名前宛ての 2 段目を送らず、Troubleshooting「起動プロンプト付きの agent start が 0.9.1 でタイムアウトし worker に名前が付かない」の回復手順に従う
- **MUST**: 作業指示プロンプトは起動プロンプトに直接 inline しない。作業指示は作業記憶(上記「作業物の置き場」参照)にファイルとして書き、起動プロンプトは「<パス> をあなた自身が読み(サブエージェントに委任しない)、その内容全体をあなたへの作業指示として忠実に実行してください。」の1行にして、2 段目の `agent prompt` で渡す。起動プロンプトの `<パス>` は、`$wb` を展開した絶対パスで書く。複数行 heredoc を `agent start` の `AGENT_ARG` にそのまま渡すと `invalid_agent_argument: agent arguments cannot be encoded safely for the target shell` で拒否された(詳細: Troubleshooting「長文プロンプトの inline 渡しが拒否される」参照)。`agent prompt` の `<TEXT>` に複数行を渡したときの挙動は確かめていない
- **MUST**: 起動プロンプトには「自分で読む(サブエージェント委任禁止)」を明記する(上記の文言に含まれている「あなた自身が読み(サブエージェントに委任しない)」を削らない)。「読み、実行してください」だけだと作業者本人が読むか委任するかが曖昧になり、fork サブエージェントへの委任という遠回りな解釈を許して初手で止まりうる(詳細: Troubleshooting「起動プロンプトのファイル読みを fork サブエージェントに委任して初手で止まる」参照)
- **MUST**: 2 段目の `agent prompt` には `--wait --until working --until blocked` を付ける。`--until` を省いた `--wait` は `idle` / `done` / `blocked` のどれかまで待つため、起動プロンプトでは worker の最初のターン(作業全体)が終わるまで戻らない。2026-10-05 の実測では、司令塔が `--wait --timeout 60000` で送ったところ、60,039 ms 後に `timeout`(`timed out waiting for agent status`)と終了コード 1 が返った。このとき submit は成功しており、直後の `herdr agent get` は `agent_status: "working"`・`interactive_ready: true` を返し、名前も保たれていた。`--until working --until blocked` を付けると受理の直後に戻るという挙動は、`herdr agent prompt --help`(0.9.1)の記述に基づくもので、実測していない(help は、submit 後 5000 ms 以内に `working` か `blocked` を観測できなければ `agent_prompt_stalled` を返すとも書いている)
- **MUST**: 2 段目が `agent_prompt_stalled` や `timeout` を返しても、submit の成否は戻り値で決めず、上記の手順5(1)の `herdr agent get` で確かめる(2026-10-05 の実測では、`timeout` が返っても submit は成功していた)
- **MUST**: エージェント名はセッション全体でユニーク制約があるため、固定名 `claude` ではなくブランチ名由来の名前にする。変換ルール: ブランチ名から prefix(`fix/` 等)を除き、`_` と `/` を `-` に置換して `claude-` を前置する(例: `fix/wt_agent_start_options` → `claude-wt-agent-start-options`)。herdr の agent 名は 1〜32 文字に制限されており(超過すると `invalid_agent_name: agent name must start with a lowercase letter and contain only lowercase letters, digits, '-' or '_' (1-32 characters)` で起動に失敗する)、変換後の名前が32文字を超える場合は、意味が保たれる範囲で単語を間引いて32文字以内に短縮する(ユニーク性が保てればよい)。実例(2026-08-01、#539): `fix/wt_agent_prompt_submit_check` → `claude-wt-agent-prompt-submit-check`(35文字)が拒否され、`claude-wt-prompt-submit-check`(29文字)に短縮して復旧した
- **MUST**: 作業者モデル(`--model <model>`)は下記「作業者モデルの選択基準」で決め、既定は `claude-opus-5-5`(司令塔=メインセッションが計画とレビュー、作業者が実装を担う分業は変わらない)。ユーザーが入力内で別モデルを指定した場合はそれに従う
- **MUST**: `--permission-mode auto` で起動する。定型操作は自動承認され、判断が必要な操作だけが blocked として表面化する
- **MUST NOT**: `--dangerously-skip-permissions` は使わない(監督を全て外すのではなく、エスカレーションのレーンを残すのが目的)
- **MUST**: それでも blocked が発生した場合、司令塔は代理承認できない(Claude Code が禁止している)。司令塔の責務は「即検知して人間に知らせる」まで(#332 の対話プロトコル参照)
- **MUST**: auto mode 起動がハーネス(auto mode 分類器)に拒否された場合、AskUserQuestion 等でユーザーに auto mode 起動の許可を明示的に確認してから再実行する(詳細: Troubleshooting「auto mode 起動の拒否」参照)
- **MUST NOT**: タスクが曖昧な場合は起動しない。**MUST**: その場合は workspace の準備完了だけ報告して終わる

#### 作業者モデルの選択基準

司令塔が「作業者にどれだけ判断を委ねるか」で決める。変更するファイル数ではなく、必要な判断の量・完了条件の検証可能性・変更が挙動に与える影響を優先する(下の effort 表にある「複数ファイル」は思考予算の目安であり、モデル選択の基準ではない)。既定は `claude-opus-5-5`(暫定運用):

| モデル | 使いどころ |
|--------|-----------|
| `claude-opus-5-5`(既定) | 既存仕様の読み解き・選択肢の比較・指示書の前提と実態が食い違ったときに自分で実測して【相談】できることが要るタスク。1 ファイルでも挙動への影響が大きければこちら |
| `claude-sonnet-5-5` | 手順・完了条件・検証方法が明確で、解釈の余地が小さいタスク(effort medium 相当)。複数ファイルでも機械的な置換ならこちら |

目的や完了条件が曖昧な場合はどちらも起動しない(上の MUST NOT のとおり、workspace の準備完了だけ報告して終わる)。

**Constraints:**
- **MUST**: 既定の見直しは手順 7 の自己更新プロトコル(issue-first)で行う。単発の失敗で既定を戻さず、同種タスクの所要時間・差し戻し回数・費用を Sonnet 作業者と比較したうえで、Issue で既定を再評価する。現行の既定は 2026-09-27 の実測(N=1: Explore 3 モデル比較 + Opus 作業者 1 件。Sonnet 作業者との同条件比較は未実施)に基づく暫定運用で、数値の詳細は #600 と vault の比較ノートを参照
- **SHOULD**: 定型タスクまで Opus にしない(単価が高い)。解釈の余地が小さいなら `claude-sonnet-5-5` を選ぶ

#### effort の選択基準

司令塔がタスクの難易度を見て判断する:

| effort | 使いどころ |
|--------|-----------|
| medium | 定型・機械的な変更(バージョン bump、typo 修正、設定1行の変更) |
| high | 通常の実装タスク(迷ったらこれ) |
| xhigh | 難しい実装・複数ファイルにまたがる変更・設計判断を含むタスク |

**Constraints:**
- **MUST NOT**: `low` は /wt では使わない(under-thinking のリスクがあるため)
- **SHOULD**: `medium` 以下では Sonnet 作業者が指示を literal に解釈する(Sonnet 5 で観測、5.5 では未検証)ため、作業指示プロンプトの完了条件を具体的に書く

#### 作業指示プロンプトのテンプレート

````
あなたは worktree <worktree-path>（ブランチ <branch-name>）で作業する実装担当エージェントです。

## タスク
<ユーザー入力を司令塔が具体化したタスク説明>

## 背景
<司令塔が把握している文脈・関連ファイルのパス・調査済みの事実>

## 完了条件
- <具体的な完了条件を箇条書き>
- 変更をコミットし、gh pr create で main 向け PR を作成する（タイトル・本文は日本語）
- 関連 Issue があれば PR 本文に Closes #<番号> を入れる

## 制約
- 作業はこの worktree 内で完結させる（リポジトリ本体には触らない）
- コミットメッセージ・PR・ドキュメントは日本語
- 判断に迷う大きな設計変更はせず、迷った点は最終報告に書く(ただし実装の方向を左右する判断は最終報告まで抱え込まず、下記「## 相談」の手順でその場でエスカレーションする。最終報告に書くのは、エスカレーションするほどではない小さな迷いの受け皿)
- ドキュメントの大規模なフォーマット変換・構造変換を行う場合、変換前にコードブロック等の不変であるべき部分を機械的に diff できるチェック(例: awk でコードブロックを抽出して新旧比較)を仕込み、変換後に意図しない変更がないことを確認する
- ライブセッション(稼働中のデスクトップ等)で検証する場合、自分が起動したプロセスの PID は起動時に `$!` で捕捉する
- ライブセッションでの検証時、名前ベースの `pgrep` で見つけた PID を kill しない
- ライブセッションでの検証時、起動・生成が確認できない場合は検証を中止して報告する(推測で続行しない)
- ライブセッションでの検証時、ユーザーの既存ウィンドウ・既存プロセスは操作しない(読み取りのみ可)
- GPG 署名で詰まった場合、`gpgconf --kill gpg-agent` 等で gpg-agent を殺さない(キャッシュ破壊で他作業者を巻き込む)。署名の失敗は「## 相談」の手順で司令塔へエスカレーションする
- CI 待ちは `gh pr checks <PR番号> --watch` を run_in_background で仕掛ける(`sleep N && gh pr checks` はハーネスに blocked されうる)。**push 直後は GitHub 側の check 登録に数秒〜十数秒のラグがあり、`--watch` が「no checks reported」で即座に失敗することがある**。その場合は失敗扱いにせず 15〜20 秒後に同じコマンドを再実行する(`gh pr checks` の exit code 8 は「pending あり」で失敗ではない)

## 相談
実装の方向を左右する判断で確信が持てないときは、最終報告まで抱え込まず、その場で司令塔へ相談を push する。判断に迷う点のうち、実装の方向を左右しない小さなものは上記「## 制約」の通り最終報告に書けばよい。

エスカレーションすべき判断の例:
- 複数の妥当な実装方式があり、どれを選ぶかで挙動やインターフェースが変わる
- Issue や指示の内容と、現状のコードベースの実態が食い違っている
- 破壊的変更(既存の挙動・データ・API 等を壊しうる変更)を伴う判断

**丸投げ禁止**: 相談には必ず「選択肢(A/B...) + 自分の推奨」をセットで送る。判断材料を示さず「どうしましょう」とだけ聞かない。

```bash
herdr agent prompt "commander-<repo名>" "【相談】<branch>: <選択肢A/B + 自分の推奨>" || true
```

相談を送ったら、司令塔からの回答(pane に届く追加指示)を待つ。回答が届くまで、相談した論点については実装を進めない。push 送信後、司令塔からの回答が長時間届かない場合、push 自体が司令塔 pane の入力欄に滞留して届いていない可能性がある(詳細: Troubleshooting「send-keys Enter が chat 入力を submit できないことがある」参照)。

- `commander-<repo名>` が見つからない等、push が失敗した場合はエラーで止まらない。返答を待ち続けると作業が止まってしまうため、その場で自分の推奨案を採用して実装を進め、判断の経緯を最終報告に書く(push はあくまで即時性のための冗長化で、必須経路ではない)
- push が成功しても、司令塔からの応答が得られないまま作業が止まる場合がある(例: 司令塔セッションが別件の権限プロンプト等で長時間ブロックされている)。この場合は無期限に待ち続けず、以下の手順でフォールバックする(`<commander-pane-id>` は `herdr agent get "commander-<repo名>"` の応答 JSON の `pane_id` で引く):
  1. `herdr pane read <commander-pane-id> --source recent --lines 20` 等で司令塔側の直近状態を複数回確認する(間隔・回数は状況に応じて判断してよいが、単発の確認だけで無応答と決めつけない)
  2. 複数回確認しても状態に変化がなければ、相談時に提示した自分の推奨案を採用して実装を進める
  3. 判断の経緯(相談を送った時刻・確認した回数・採用した推奨案とその理由)を最終報告および成果物(PR本文等)に明記する
  4. 事後に司令塔からの応答が届いた場合は、既に進めた実装との整合を確認し、応答内容と食い違う変更があれば追従する

## 報告
報告の正はこの会話へのテキスト出力(司令塔が `herdr agent read` で回収する)。**`SendMessage` は使わない** — 作業者は自セッションの main のため司令塔という宛先が存在せず、`You are the main conversation` エラーになる。

完了したら、変更ファイル・PR の URL・確認した動作を簡潔にまとめてこの会話に書く。指示外の気づき（環境の摩擦・想定外の挙動・自分で編み出した回避策）があれば、解決済みであっても必ず報告する（該当なしなら「なし」と明記する）。

会話内報告に加えて、完了時に司令塔へ1行の push 報告を送る(フォーマット: `【報告】<branch>: <一行サマリ>（<PR URL>）`。詳細は上記の会話内報告に書き、push は要約1行のみでよい):

```bash
herdr agent prompt "commander-<repo名>" "【報告】<branch>: <一行サマリ>（<PR URL>）" || true
```

- `commander-<repo名>` が見つからない等、push が失敗した場合はエラーで止まらず、会話内報告のみに縮退して続行する(push はあくまで即時性のための冗長化で、必須経路ではない)
````

**Constraints:**
- **SHOULD**: 背景と完了条件を具体的に書く(書くほど作業品質が安定する)
- **MUST**: テンプレート中の `commander-<repo名>`(【相談】【報告】の push 2箇所と、「## 相談」の無応答フォールバックの `herdr agent get` の計3箇所)はプレースホルダ。司令塔が手順3で実際に名乗った名前(サフィックス付きの場合はそれを含む)に置き換えてから作業者に渡す

### 5. 対話プロトコル(委任後の監視と対話)

エージェント起動後、司令塔(このセッション)と作業者エージェントの間のやり取りは、以下の4本柱からなる対話プロトコルとして運用する(設計の背景は #332、上り=内容の push 設計は #341 参照)。(4) 供養 は `/wtclean` 側で扱う。

#### (1) 下り=指示

委任時の指示は手順4のファイル渡し方式(作業記憶へのファイル書き込み+1行の起動プロンプト)で渡す。委任後に追加の指示を送りたい場合は、`herdr agent prompt <agent-name> "<追加指示のテキスト>"` の1コマンドで送る。agent 名を直接ターゲットにできるため pane-id の引き直しが不要になる。作業者からの【相談】(手順4テンプレート「## 相談」参照)への回答もこの手順で送る(詳細な判別・応答フローは下記(2)「相談 idle の判別」参照):

```bash
herdr agent prompt <agent-name> "<追加指示のテキスト>"
```

**Constraints:**
- **MUST**: `<agent-name>` は手順4でエージェントに付けたユニーク名をそのまま使う。pane-id の引き直しは不要
- **MUST**: 実行前に対象の agent 名を必ず確認する(宛先を誤ると、無関係なエージェントに指示が届いてしまう。`agent prompt` はテキストを引数としてそのまま送るだけで、確認や取り消しは挟まらない)
- **MUST**: 送信前に `herdr agent read` で対象 pane の状態を確認する。AskUserQuestion 等のメニューが表示中は `agent prompt` を使わない(chat 入力欄への送信になるため、ハイライトされている選択肢を誤確定させる罠がある。`send-text` + Enter でこの誤確定による実害が実際に出ており(詳細: Troubleshooting「AskUserQuestion メニュー表示中の誤確定事故」参照)、`agent prompt` も同じくメニュー表示中の pane に送信する以上、予防的に避ける)。メニューの選択肢確定自体は従来どおり `herdr pane send-keys <pane-id> Enter` で行う(pane-id は `herdr agent get <agent-name>` で都度引く。詳細: Troubleshooting「pane-id は非永続」参照)
- **MUST**: 送信前の `herdr agent read` では、メニュー表示の有無に加えて**入力欄の pending テキストの有無**も確認する。`agent prompt` は入力欄の pending テキストを新テキストで置換するため、ユーザー由来と思われるテキスト(【相談】【報告】プレフィックスが付いていない未送信テキスト)が残っている場合は置換で消さず、ユーザーに確認するか、送達(手動 Enter)を待ってから送る(詳細: Troubleshooting「agent prompt がユーザー由来の pending テキストを置換で消しうる」参照)
- **MUST**: `agent prompt` 送信後は `herdr agent get <agent-name>` で `working` へ遷移したことを確認する。コマンドは `agent_prompted` を正常に返すが、それだけでは submit の成否を判定できない(詳細: Troubleshooting「send-keys Enter が chat 入力を submit できないことがある」参照)。遷移せずテキストが入力欄に残っている場合は、`herdr agent read` で pane の状態(メニュー非表示であること。上記 Constraint 参照)を確認したうえで `herdr pane send-keys <pane-id> Enter` で submit する(pane-id は `herdr agent get <agent-name>` で引く)
- **MUST**: レビュー差し戻し等、委任後に追加の作業ラウンドを送る前に、`herdr agent get <agent-name>` で pane-id を引いたうえで `herdr pane read <pane-id> --source visible` を実行し、末尾行の pane 下部ステータスラインで context 使用率(💭 n%)を確認する。50% を超えている場合は追加ラウンドを送らず、(a) 司令塔が直接対応する、(b) 新 worker へ引き継ぐ(引き継ぎブリーフ = 元ブリーフ + ここまでの成果物参照(PR URL / コミット)+ 残作業のみ。引き継ぎ指示・HANDOFF.md・後任ブリーフの具体手順は手順8「引き継ぎモード」参照)、のいずれかを選ぶ。ユーザーより先に司令塔が検知すべきシグナルであり、閾値超過を検知したら対応方針とあわせてユーザーに報告する(詳細: Troubleshooting「レビュー差し戻しラウンドによる worker context の逼迫」参照)
- **MUST**: pane 幅が狭くステータスラインが `…` で切り詰められ 💭 の値が読めない場合、herdr CLI に幅非依存で context 使用率を取得できる経路は無い(実機調査済み。詳細: Troubleshooting「ステータスライン切り詰めで 💭 が読めない」参照)。読めない場合は使用率を推測で埋めず、保守的に (a) 直接対応 または (b) 引き継ぎ 側へ倒す
- **MAY**: `--wait` / `--until <STATUS>`(繰り返し指定可)/ `--timeout <MS>` を併用すると、送信と応答待ちを1コマンドに畳められる(詳細: Troubleshooting「send-keys Enter が chat 入力を submit できないことがある」参照)

#### (2) 上り=イベント

委任直後、作業者の状態が `working` に遷移したことを確認してから、`herdr agent wait` で状態遷移を待ち受ける(詳細: Troubleshooting「wait の即時解決」参照)。`--until` を省略した場合のデフォルトで `idle` / `done` / `blocked` のいずれかにマッチして戻ってくるため、1コマンドで済む:

```bash
# gotcha: 対象が既に指定ステータスだと即座に解決してしまうため、working に遷移済みか確認してから仕掛ける
AGENT_NAME=<agent-name>
herdr agent get "$AGENT_NAME"

herdr agent wait "$AGENT_NAME" > "<司令塔自身のスクラッチパッドディレクトリ>/wait-${AGENT_NAME}.json"
```

発火後、出力 JSON に含まれるステータスを確認して分岐する。`blocked` ならユーザーに承認を仰ぎ、`idle` / `done` なら `herdr agent read "$AGENT_NAME" --source recent --lines 50` で完了報告を確認する(`idle` の場合は完了と断定せず下記「相談 idle の判別」も併せて行う)。

**Constraints:**
- **MUST**: ログファイル名には `<agent-name>` を含める。複数 worktree を並行監視しているときに固定ファイル名だと内容が上書きされてしまうため
- **MUST**: 出力先は司令塔自身のスクラッチパッドディレクトリ(システムプロンプトに明記されるセッション固有の `/tmp/claude-<uid>/<cwd正規化>/<session-id>/scratchpad`)配下とする。`/tmp` 直下の固定パスは読み取り時に権限分類器の確認対象になりうるため使わない。2026-07-19(#446 の運用中)、司令塔が `/tmp/wait-idle-<agent-name>.json` を `cat` する Bash コマンドが権限確認プロンプト(`Yes, allow reading from tmp/ from this project`)で停止し、作業者の【相談】に長時間応答できなくなった(#462。作業者側の影響は #463)
- **MUST**: `<agent-name>` は手順4でエージェントに付けたユニーク名。`herdr agent wait` / `herdr agent read` は pane-id ではなく agent 名を直接ターゲットにできるため、監視中に pane-id を引き直す必要がない
- **MUST NOT**: 定期ポーリング(`herdr pane list` 等を一定間隔で呼び続けるループ)は禁止。コストが高いうえ、このプロトコルが解消したいアンチパターンそのもの
- **MUST**: 特定のステータスだけを待ちたい場合は `--until <STATUS>` を明示する(繰り返し指定可、例: `--until blocked --until idle`)。`done` は herdr 0.7.5 以降 `--until` / デフォルトの両方で受理される(詳細: Troubleshooting「herdr agent wait の done 受理(0.7.5)」参照)
- **MUST**: 似た用途で `herdr wait agent-status <pane-id> --status <...|done|...>` というコマンドもあるが、こちらは pane-id が必須の UI 向けのコマンド。CLI 主導のこのプロトコルでは agent 名を直接使える `herdr agent wait <agent-name>` を使う
- **MAY**: `--timeout`(ミリ秒)は省略可能で、省略すると無期限にブロックする。バックグラウンドで放置する分には問題ないが、安全弁として妥当な値を指定してもよい
- **MUST**: タイムアウトした場合は同じ wait を仕掛け直す(これは定期ポーリングではなく、イベント待ちの再武装)

**相談 idle の判別:**

作業者は【相談】送信後も司令塔からの回答を待つ間 `idle` に遷移する(手順4テンプレート「## 相談」参照)。また、作業者の bash が `sleep` 主体の待ち(実機検証のポーリング等)に入ると、完了前でも一時的に `idle` が発火することがある(フラップ)。そのため `idle` 発火は「完了」「相談待ち」「作業続行中のフラップ」のいずれもありうる。

- **MUST**: `idle` 発火時は完了と断定せず、`herdr agent read "$AGENT_NAME" --source recent --lines 50` で直近ログを確認し、次の3通りで判定する: (1) 末尾付近に `【相談】` がある → 「相談待ちの idle」、(2) 完了報告がある → 「完了の idle」、(3) spinner が稼働中で最終報告がまだ無い → 「作業続行中のフラップ」
- **MUST**: 「作業続行中のフラップ」と判定したら、作業者が `working` に遷移したことを `herdr agent get` で確認してから `herdr agent wait` を仕掛け直す(これはポーリングではなくイベント待ちの再武装。詳細: Troubleshooting「sleep 主体フェーズで idle が完了前に一時発火する」参照)
- **MUST**: 「相談待ちの idle」と判定したら、上記(1)「下り=指示」の手順(`herdr agent prompt <agent-name> "<回答>"`)で回答を返す。回答後は作業者が再び `working` に遷移したことを確認したうえで、`herdr agent wait` を仕掛け直す(詳細: Troubleshooting「相談待ち idle と完了 idle の判別」参照)

#### (3) 上り=内容

作業者からの報告内容そのもの(進捗・完了・気づき)を受け取るチャネル。主チャネルはあくまで手順5(2)の `herdr agent wait` で、作業者が `idle`/`blocked` に遷移したのを検知してから `herdr agent read "$AGENT_NAME" --source recent --lines 50` で会話内容を読みに行くプル型。

作業者は完了時、上記のプル型に加えて司令塔へ1行の push 報告も送る(作業指示プロンプトの「## 報告」欄に規定。手順4「作業指示プロンプトのテンプレート」参照)。push はこのプロトコルの主チャネルではなく、agent wait が発火する前に司令塔の手が空いていた場合などに拾える即時性のための副次的な冗長化と位置づける。

作業者はこれとは別に、完了を待たず判断に迷った時点で【相談】push を送ることがある(作業指示プロンプトの「## 相談」欄に規定。手順4「作業指示プロンプトのテンプレート」参照)。【報告】が完了時の事後報告なのに対し、【相談】は判断時点でのエスカレーションで、送信後に作業者が `idle` 化する点が異なる。判別と応答の手順は上記(2)「相談 idle の判別」を参照。

**Constraints:**
- **MUST**: `idle`/`blocked` の検知は push の有無に関わらず `herdr agent wait`(手順5(2))で行う。push は agent wait を代替しない
- **MUST**: 報告フォーマットは `【報告】<branch>: <一行サマリ>（<PR URL>）`。詳細は会話内報告(プル型で回収する側)に書き、push は要約1行のみ
- **MUST NOT**: push の失敗(`commander-<repo名>` が見つからない等)を理由に作業者の完了報告そのものを止めない。push はベストエフォートで、失敗時は会話内報告のみに縮退する

### 6. PR のマージ世話

作業者から PR 作成の完了報告(`idle`)を確認したら、司令塔はマージ可否を判断する(背景: #355)。マージ可能なのは以下の3条件が揃った(AND)ときだけ:
- required checks がすべて通過している
- base ブランチに追随できている(BEHIND でない)
- conversation がすべて解決している(未解決の review thread がない)

```bash
gh pr view <PR番号> --json mergeStateStatus --jq .mergeStateStatus
```

`mergeStateStatus` 別の対応:

| mergeStateStatus | 対応 |
|--------|-----------|
| BEHIND | `gh pr update-branch <PR番号>` で base に追随させる |
| CLEAN | マージしてよい(実行はユーザー承認のもとで)。ただし push 直後の CLEAN は仮 CLEAN の可能性がある(下記 Constraints 参照) |
| DIRTY | コンフリクトあり。作業者に rebase/merge を差し戻すか、ユーザーにエスカレーションする |
| BLOCKED | 単体では判別不能な複合ステータス。下記の GraphQL で切り分ける(詳細: Troubleshooting「BLOCKED は複合ステータス」参照) |

`BLOCKED` 検知時は reviewThreads の未解決数を確認する:

```bash
gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviewThreads(first: 100) { nodes { isResolved } }
      }
    }
  }' -f owner=<owner> -f repo=<repo> -F pr=<PR番号> \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length'
```

**Constraints:**
- **MUST**: `BLOCKED` を検知したら、CI実行中と conversation 未解決を区別するため上記 GraphQL で reviewThreads の未解決数を確認する
- **MUST**: 未解決の review thread が1件以上あれば、CI結果を待たずに即エスカレーションする(作業者へ差し戻すか、ユーザーに報告する)
- **MUST**: 未解決の review thread が0件なら、required checks の完了を待つ
- **MUST**: 複数 PR を直列にマージする場合、1本マージするたびに残りの PR が base 更新で BEHIND に戻る玉突きを前提にループを設計する(全PRを一度に判定してから順にマージ、ではなく「1本マージ→残りのステータスを再取得→次を判定」を繰り返す)
- **MUST**: マージ実行の直前に `mergeStateStatus` を再取得し、`CLEAN` であることを確かめてから `gh pr merge` を実行する。判定時点の `CLEAN` を使い回さない(CLEAN 確認とマージ実行の間に Copilot レビューが割り込む TOCTOU がある — #542、#388。詳細: Troubleshooting「push 直後の CLEAN は仮 CLEAN」)
- **MUST**: push(`gh pr update-branch` を含む)から間もない `CLEAN` は、Copilot 自動レビュー未着弾の暫定値(仮 CLEAN)とみなす。Copilot の自動レビューは push から着弾まで1〜2分かかるため、最新 push から少なくとも2分待ってから reviewThreads の未解決数(上記 GraphQL)を最終チェックする。15秒待ちでは着弾が間に合わず防げなかった実例がある(#388)
- **MAY**: 着弾の手がかりとして `gh pr view <PR番号> --json headRefOid,reviews --jq '{head: .headRefOid, reviewed: [.reviews[] | select(.author.login == "copilot-pull-request-reviewer") | .commit.oid]}'` で Copilot レビューが最新コミットに付いたかを見てよい。ただし Copilot は push ごとに必ず再レビューするとは限らないため、「最新コミットへのレビュー着弾」をマージの必須条件にはしない(来ないレビューを待ち続けることになる)
- **MUST**: マージが「base branch policy prohibits the merge」で拒否されたら、`CLEAN` 表示を信用せず reviewThreads を再取得する(この拒否は conversation 割り込みのシグナル)。未解決 thread があれば上記の即エスカレーションに合流する
- **MUST NOT**: `mergeStateStatus` が `CLEAN` になる前にマージを実行しない
- **MUST NOT**: マージ時に `--delete-branch` を付けない。worktree が生存中はローカルブランチ削除が必ず失敗して紛らわしいため、ブランチ削除(リモート含む)は `/wtclean` の領分とする

### 7. 自己更新(Self-update)

運用中に踏んだ罠・バグ・環境摩擦の知見を、該当する skill/command の SOP に還流するプロトコル(背景: #358)。入力は以下のいずれか:
- 作業者からの気づき報告(作業指示プロンプトの「## 報告」欄。手順5(2)で `idle` 確認時に読む)
- `/wtclean` の供養ステップ(手順6「知見の回収(供養)」)で抽出された Issue 候補
- 司令塔自身の運用ミス(例: pane-id の宛先誤り、ローカル main 更新漏れ)

**Constraints:**
- **MUST**: 司令塔はフィルターを適用する。「再発しうる」かつ「タスク横断的」な知見のみを対象とし、1回きり・タスク固有の知見は対象外とする(過学習による SOP 肥大化の防止)
- **MUST**: フィルターを通過した知見は、該当する skill/command の diff 案(Constraint 追記または Troubleshooting 追記)として Issue 化する
- **MUST**: フィルターを通過した教訓を Issue 化する際、llm/context/outcomes.md(未整備の場合は Issue #395 を参照)の外部アウトカム①-③のどれに効くか(どれでもなければ『プロセス改善のみ』)を Issue 本文に1行で明記する
- **MUST**: 実装は issue-first(まず Issue 化)→ 作業者へ委任 → PR 作成 → 人間レビュー・マージ、という既存ゲート(手順4)と同じフローを通す
- **MUST NOT**: 司令塔・作業者が自分でマージしない。自己更新は「自己起案」であって「自己マージ」ではない(自分の行動規範を自分で書き換えるループは、誤った教訓の一般化が全後続エージェントに複利で効くため、人間ゲートを安全弁として維持する)

### 8. 引き継ぎモード(worker 交代)

手順5(1) の 50% Constraint で「(b) 新 worker へ引き継ぐ」を選んだ場合の実行手順。前任 worker への引き継ぎ指示、HANDOFF.md の様式、後任 worker のブリーフ、HANDOFF.md のライフサイクルを規定する(2026-08-02 の実戦運用を標準化。背景: #553)。

#### 引き継ぎ指示(前任 worker へ)

司令塔が `herdr agent prompt <agent-name>`(手順5(1)参照)で前任 worker へ送る指示は、以下の5点をこの順で含める:

```
以下の5点を守ってください:

1. 新規着手禁止: これ以降は新しい作業項目に着手しない
2. 区切りまで仕上げ: 進行中の変更をコンパイル/チェックが通る最小の区切りまで仕上げる
3. 署名コミット: 計画のコミット分割方針に沿ってコミットする(粒度は粗くてよい)
4. HANDOFF.md 書き出し: worktree ルートに以下の5点セットで作成する(コミットに含めない。様式は下記「HANDOFF.md の様式」参照)
5. 停止: 報告して終了する(PR 作成はしない)
```

**Constraints:**
- **MUST**: 5点を過不足なく、この順で含める
- **MUST NOT**: 前任に PR 作成やレビュー対応を続けさせない(5番目の「停止」が前任の最終ステップ)

#### HANDOFF.md の様式

worktree ルートに以下の5点セットで書く:
- (a) 完了した項目(計画の C 番号・コミット hash 対応)
- (b) 未完了項目と残作業のファイル単位リスト
- (c) 実装中に下した判断と計画からの差分
- (d) ハマった点・回避策・次の作業者への注意
- (e) 検証状態(何が通っていて何が未実行か)

**Constraints:**
- **MUST**: 5点とも省略しない((c)(d) は特に後任の手戻りを防ぐ)
- **MUST**: HANDOFF.md はコミットに含めない(untracked のまま置く。理由は下記「HANDOFF.md のライフサイクル」参照)

#### 後任ブリーフ(新 worker へ)

後任 worker の起動プロンプトは手順4のテンプレートを踏襲しつつ、以下を追加/変更する:
- 最初に読むものの順序を明示する: **HANDOFF.md → 承認済み実装計画 → 正典 docs** の順
- 残作業(HANDOFF.md の (b))と司令塔補足を「## タスク」「## 背景」に反映する

**Constraints:**
- **MUST**: 前任の署名コミットを rebase/amend しない(区切りまで仕上げた署名コミットが引き継ぎの前提であり、履歴の書き換えはその前提を壊す)
- **MUST**: 50% ルールを後任のブリーフにも最初から組み込む(引き継ぎは連鎖しうるため。手順5(1) の Constraint 参照)
- **MUST**: 後任 agent 名は前任の名前(手順4の変換ルール参照)に数字サフィックスを付けた連番とする(例: `claude-wt-agent-start-options` → `claude-wt-agent-start-options-2`。手順3の司令塔自己命名の数字サフィックス運用と同じ考え方)
- **MUST**: 連番付与後の名前にも手順4の32文字制限と短縮規定(手順4「pane の用意とエージェント起動」の名前変換ルール参照)が適用される。サフィックスの分だけ前任より長くなるため、前任が32文字以内でも超過しうる。例: `claude-breaking-cleanup-cutover-2`(33文字)は拒否されうるため `claude-cutover-2`(16文字)に短縮する

#### HANDOFF.md のライフサイクル

1. **untracked のまま置く**: `/wtclean` の未コミット変更チェックが、引き継ぎ文書の残る worktree を誤って削除しない安全弁として偶然機能する(`/wtclean` 側の複数 worker 対応は #552 参照)
2. **削除前に作業記憶へアーカイブする**: `cp` で作業記憶(手順4「作業物の置き場」参照)へ `<YYYYMMDD>-handoff-<branch-slug>.md` としてコピーし、先頭に `kind: handoff` の frontmatter を付ける。HANDOFF.md は `/wtclean` の供養の素材で、供養は別のセッションで行われることがある。セッションが終わると消えるスクラッチパッドに置くと、供養の前に失われうる。削除後は worktree 側に実体が残らないため、アーカイブを削除より先に行う
3. **PR 作成前に削除する**: アーカイブ済みであることを確認したうえで削除する

**Constraints:**
- **MUST**: アーカイブしてから削除する(逆順にすると供養素材が失われる)
- **MUST NOT**: HANDOFF.md をコミットに含めない(上記「HANDOFF.md の様式」の Constraint と同じ理由)

### 9. 司令塔の context 使用率の自己確認(途中の書き出し)

司令塔は、作業の途中で自分の context 使用率を確かめ、閾値を超えたら途中の状態を状態ファイルに書き出す(#658)。自動の要約(compaction)が走ると、冒頭で読んだ SOP や判定の途中の結論が会話から落ちうるため、要約の前に状態を会話の外へ逃がしておく。

```bash
herdr pane read "$HERDR_PANE_ID" --source visible
```

**Constraints:**
- **MUST**: 司令塔は、worker の完了報告を処理するたびと PR をマージするたびに、上記のコマンドで自分の pane の末尾のステータスラインを読み、context 使用率(💭 n%)を確かめる
- **MUST**: 使用率が 70% を超えたら、司令塔は途中の状態を状態ファイルに書き出し、新しいセッションで続けるか締めるかをユーザーに相談する。70% は暫定の閾値で、運用して見直す
- **MUST**: 状態ファイルの置き場と書式は、`~/.claude/skills/wtclose/SKILL.md` の「状態ファイルの書式」節に従う。司令塔はこの節を Read ツールで読む
- **MUST NOT**: 途中の書き出しのために `wtclose` を Skill ツールや `/wtclose` で呼ばない。呼んだ時点で締めの検問(Stop hook)が登録され、締めの条件がそろうまでターンを終えられなくなる
- **MUST**: ステータスラインが切り詰められて 💭 の値が読めない場合、司令塔は使用率を推測で埋めず、閾値を超えたものとして書き出す(Troubleshooting「ステータスライン切り詰めで 💭 が読めない」参照)
- **MUST**: 締めるときは `wtclose` を呼ぶ。途中の書き出しは締めの代わりにならない

## Examples

```
/wt CIのキャッシュが壊れてるのを直したい
/wt nvimにcopilot連携を追加する
```

## Troubleshooting

### mise trust 忘れ
mise trust は絶対パス単位で管理されるため、新規 worktree は毎回 untrusted で始まる。忘れると `mise run` が「no tasks defined」で失敗する — #335。

### allowlist テンプレートの cp 失敗
`~/.claude` への反映は home-manager 経由で、`mise run nix:switch` を実行しないと `~/.claude/templates/` に反映されない。`cp` が `No such file or directory` で失敗したら、まず nix:switch 漏れを疑う。

### auto mode 起動の拒否
auto mode での起動自体がハーネス(auto mode 分類器)に「ユーザーの明示許可がない」として拒否されることがある。その場合は AskUserQuestion 等でユーザーに auto mode 起動の許可を明示的に確認してから再実行する。

### 長文プロンプトの inline 渡しが拒否される
`herdr agent start` の `--` 以降(`AGENT_ARG`)に複数行 heredoc の作業指示プロンプトをそのまま渡すと、`invalid_agent_argument: agent arguments cannot be encoded safely for the target shell` で拒否される(2026-07-30、#520 で実機確認)。回避策: 作業指示をファイルとして書き(置き場は手順4「作業物の置き場」の作業記憶。当時はスクラッチパッドだった)、起動プロンプトは「<パス> をあなた自身が読み(サブエージェントに委任しない)、その内容全体をあなたへの作業指示として忠実に実行してください。」の1行にする。#520 の当時は、この 1 行を `agent start` の引数で渡していた。herdr 0.9.1 では起動プロンプト付きの `agent start` がタイムアウトして worker に名前が付かないため、司令塔はこの 1 行を `agent start` には付けず、起動後に名前宛ての `herdr agent prompt` で渡す(手順4「pane の用意とエージェント起動」の 2 段目と、下記「起動プロンプト付きの agent start が 0.9.1 でタイムアウトし worker に名前が付かない」参照)。allowlist テンプレート(手順3「worktree の準備」参照)は「司令塔がタスク指示を置く作業記憶の読み書き」を既に許可しており、この方式と整合している。

### pane split 直後の agent start が agent_pane_busy で拒否される
2026-09-27 の並行運用で、司令塔が `herdr pane split` の直後に同じコマンド列で `herdr agent start` を投げたところ、`agent_pane_busy`(`agent target pane w4V:p2 is not an available shell`)で拒否された(#614)。pane split 直後は pane 内のシェルがまだ起動しておらず、前面プロセスがシェルとして使える状態になるまでラグがあるため、直後の `agent start` はタイミング依存で失敗しうる。同日 2 回発生し(#596・#611 の worker 起動時)、2 回目は 5 秒待ってから同じコマンドを再実行して成功した。`agent_pane_busy` を受けたら失敗扱いにせず、数秒後に同じコマンドを再実行する(2 回目で通る)。予防策として、起動前に `herdr pane process-info --pane <pane-id>` で前面プロセスがシェルになったことを確認する(手順4「pane の用意とエージェント起動」参照)。

### 起動プロンプト付きの agent start が 0.9.1 でタイムアウトし worker に名前が付かない
2026-10-04、herdr 0.9.1(クライアント・サーバーとも)の環境で、司令塔は当時の手順4のとおり、起動プロンプトを `herdr agent start` の引数に付けて worker を起動した。約 30 秒後に `{"error":{"code":"timeout","message":"timed out waiting for agent startup"}}` が返り、worker に名前が付かなかった(#664)。worker 自体は起動しており、起動プロンプトの作業を進めていた。`herdr agent get <名前>` は `agent_not_found` を返し、`herdr agent list` ではその worker が `name: null` で載っていた。司令塔は、pane ID を宛先にして `agent get`・`agent wait`・`agent read`・`agent prompt` を通し、セッションの最後まで pane ID で運用した。

2026-10-05、司令塔は同じ形(`herdr agent start <名前> --kind claude --pane <pane-id> -- --model <model> --effort <effort> --permission-mode auto "<起動プロンプト 1 行>"`)で 5 体の worker を並行に起動し、5 体とも同じ結果になった(5/5 で再現)。5 体とも、約 30 秒(既定の `--timeout 30000`)後に `timeout` エラーと終了コード 1 が返り、直後の `herdr agent get <名前>` は `agent_not_found` を返した。`herdr agent list` では、5 体とも `name: null`・`agent_status: "working"` で、`cwd` は正しい worktree だった。worker は起動プロンプトを受け取って作業しており、うち 1 体が送った【相談】(`herdr agent prompt "commander-dotfiles" "…"`)は司令塔に届いた。同じ日、司令塔は 6 体目を起動プロンプトなしで起動した。`agent start` は約 4.0 秒で終了コード 0 を返し、結果 JSON の `result.agent` には付けた名前・`"agent_status":"idle"`・`"interactive_ready":true` が入っていた。直後の `herdr agent get <名前>` も成功した。続けて司令塔が名前宛ての `herdr agent prompt <名前> "<起動プロンプト 1 行>" --wait --timeout 60000` で起動プロンプトを渡したところ、起動プロンプトは worker に届いた。ただし `--wait` は 60,039 ms 後に `timeout`(`timed out waiting for agent status`)と終了コード 1 を返した。`--until` を省いた `--wait` は `idle` / `done` / `blocked` まで待つので、worker の最初のターンが終わるまで戻らないためである。直後の `herdr agent get <名前>` は `agent_status: "working"`・`interactive_ready: true` を返し、名前も保たれていた。

原因は確かめていない。推測(未検証)は次のとおり: 起動プロンプトを引数で渡すと、worker はすぐ `working` に入る。そのため herdr は「入力待ち(interactive readiness)」を `--timeout` の間に観測できず、タイムアウトする。名前の登録は、起動が成功したときにだけ行われる。`herdr agent start --help`(0.9.1)の文面「The pane must be at its interactive shell prompt. Success means the expected agent was detected in the same terminal and is ready for input.」と、末尾の案内「next: herdr agent prompt <TARGET> <TEXT> --wait」は、この推測と整合する。

司令塔は、手順4の 2 段(起動プロンプトなしの `agent start` → 名前宛ての `agent prompt`)で worker を起動する。それでも `agent start` が `timeout` を返した場合や、起動プロンプト付きで起動してしまった場合は、次の手順で回復する:
1. 司令塔は `herdr agent list` で、対象の pane ID の worker が `name: null` で載っていて、`cwd` が対象の worktree であることを確かめる
2. 司令塔は、そのセッションの間、その worker の宛先を名前ではなく pane ID にして手順5を回す(`agent get`・`agent wait`・`agent read`・`agent prompt` は pane ID 宛てで通る。2026-10-04 に 4 つとも、2026-10-05 に `agent prompt` を実機で確かめた)。起動プロンプトをまだ渡していない場合(起動プロンプトなしの 1 段目がタイムアウトした場合)は、2 段目の `agent prompt` も pane ID 宛てで送る。pane ID は非永続なので(下記「pane-id は非永続」参照)、司令塔は pane ID 宛てに送る前に `herdr agent list` で pane ID と `cwd` の対応を確かめ直す
3. 司令塔は、名前の付かなかった worker を `herdr agent rename` で名付け直さない(手順3「司令塔の自己命名」の MUST NOT)

worker から司令塔への push(【相談】【報告】)は、司令塔の名前を宛先にするので、worker に名前が付かなくても影響を受けない(2026-10-05 に、名前の付かなかった worker の【相談】が司令塔に届いた)。

### 起動プロンプトのファイル読みを fork サブエージェントに委任して初手で止まる
2026-09-27 の 7 体並行運用で、作業者 1 体(Sonnet 5 / effort high)が当時の起動プロンプト「<パス> を読み、その内容全体をあなたへの作業指示として忠実に実行してください。」を受けて、ファイルを自分で読まず Agent ツール(`subagent_type: fork`)に読ませ、そのままターンを終えて done になった(#609)。fork の結果通知が届かず、司令塔が `agent prompt` で「サブエージェントに委任せず自分で cat して実行」と差し替えるまで止まった(約 8 分のロス)。起動プロンプトが「読み、実行してください」だけだと、作業者本人が読むか委任するかが曖昧で、fork への委任という遠回りな解釈を許してしまう。起動プロンプトには「あなた自身が読み(サブエージェントに委任しない)」を明記する(手順4「pane の用意とエージェント起動」参照)。

### ライブセッション検証時の誤 kill 事故
2026-07-05、作業者エージェントが検証用に起動したはずの Alacritty が実際にはマップされておらず、直後に `pgrep -af alacritty` で拾った PID をテスト用ウィンドウと誤認して kill し、ユーザーが元から開いていた既存の Alacritty(workspace 2)を誤終了させた(#354、PR #353)。自分が起動したプロセスは起動時の `$!` で PID を捕捉して追跡し、事後に名前ベースの `pgrep` で「自分のものらしきプロセス」を探して kill するのは禁止。

### worktree での headless nvim 起動の成否は検証シグナルにならない
worktree で Neovim 設定(`.config/nvim/*.toml` 等)を変更するタスクで `XDG_CONFIG_HOME=<worktree>/.config nvim --headless "+qa!"` を検証に使うと、変更内容とは無関係なプラグイン層起因のエラーが出て、起動の成否が変更の正しさのシグナルとして機能しないことがある。原因は構造的なもので、実機の `~/.config/nvim` は home-manager が最後の `nix:switch` 時点の設定を配布したもの(Nix store への symlink)であり、プラグインキャッシュと state(dpp.vim の `~/.cache/dpp` 配下の `repos/`・`state.vim`・`startup.vim`)もその実機設定を前提に生成・インストールされている。worktree の `.config/nvim` はそれと食い違うため、headless 起動は「worktree の設定 × 実機のキャッシュ / state」という混ざった状態を検証してしまう。さらに `init.lua` の `dpp_base` は `XDG_CACHE_HOME` ではなく `$HOME/.cache/dpp` で決まるため、`XDG_CONFIG_HOME` だけを worktree に向けて起動すると worktree の設定で実機の state を読み、再生成まで走らせうる(state 鮮度管理の経路は `docs/reference/neovim-config.md` の「Plugin Management (dpp)」章参照)。

実例(dein 時代): 2026-07-18、#444(telescope.nvim 廃止)の検証で、変更後の headless 起動は dein 内部で `E897: List or Blob required`(`dein#source` 経由)、切り分けのため `git stash` で変更前に戻して再実行すると別種のエラー(`ddc.vim` の `hook_source` 失敗、`lspconfig` 非推奨警告)が出た。どちらも telescope/ddu とは無関係で、変更前後どちらでも「その時点のエラー」が出る状態だった(#453)。当時の原因は dein のプラグインキャッシュ・自動インストール状態の食い違いだが、dpp.vim へ移行した現在も「worktree の設定と実機のキャッシュ / state が食い違う」構造は変わらない。

教訓: Neovim 設定を変更するタスクでは、headless 起動の「エラーなし=正しい」を当てにせず、以下を標準の検証手順とする:
1. 静的検証: `grep` での参照漏れチェック、`git diff` での意図しない変更(特に PUA グリフ等の非ASCII文字を含む箇所)の不在確認、TOML 構文チェック(例: `python3 -c "import tomllib, sys; tomllib.load(open(sys.argv[1], 'rb'))" .config/nvim/ddc_settings.toml`。パスは変更した TOML に置き換える。成功時は無出力で exit 0、構文エラー時は `TOMLDecodeError` で exit 1)
2. ベースライン比較: 変更前の状態(一時 WIP コミットや `git worktree` の別チェックアウト等)で同じ headless コマンドを実行し、エラーの有無・種類を比較する。変更前後どちらでも同じ(無関係な)エラーが出るなら、そのエラーは環境由来と判断してよい
3. 実際に起動して確かめる必要がある場合は、次項の XDG_* 5点セットでキャッシュ / state ごと隔離した環境で行う
4. headless 検証が不安定な場合は無理に続行せず、静的検証で代替した旨を最終報告に明記する

### worktree での headless nvim 隔離検証は XDG_* 5点セット必須
2026-07-26、#495 の隔離検証(PR #500)で `HOME` 環境変数だけをスクラッチディレクトリへ上書きして headless nvim を起動したところ、修正後にもかかわらず `[ddc] Not found source: cmdline-history` が出続け「まだ直っていない」ように見えた(偽陰性)。原因は、このリポジトリの Nix (home-manager) セットアップが `XDG_CONFIG_HOME` / `XDG_CACHE_HOME` / `XDG_STATE_HOME` / `XDG_DATA_HOME` をログインシェルのグローバル環境変数として実ホームのパスに固定しており、`HOME` より優先されること。`vim.fn.stdpath('config')` 等はこれらの `XDG_*` を先に見るため、`HOME` だけの上書きでは隔離が漏れ、headless nvim は隔離先ではなく実ファイル(未修正の設定)を読んでしまう。`HOME` に加えて4つの `XDG_*` もすべてスクラッチディレクトリへ上書きして再検証したところ、正しく隔離された状態で修正の効果(`Not found source` が0件、`sourced: true`)を確認できた(#501)。

教訓: worktree での headless nvim 隔離検証(dpp state 再生成の事前確認など)では、`HOME` に加えて `XDG_CONFIG_HOME` / `XDG_CACHE_HOME` / `XDG_STATE_HOME` / `XDG_DATA_HOME` の4変数もスクラッチディレクトリへ明示的に上書きする(計5点)。`HOME` だけ、あるいは `XDG_CONFIG_HOME` だけの片側上書きは、前項の通り dpp の state が `$HOME/.cache/dpp`、設定が `stdpath('config')` と別々の変数で決まるため、どちらかが実機側に漏れる。

### send-text は単体では実行されない
`pane send-text` は pane の入力欄にテキストを挿入するだけで、送信(実行)はされない。実機確認済み: `send-text` の直後に `pane read` してもコマンドは未実行のまま入力欄に残っており、続けて `pane send-keys <pane-id> Enter` を送って初めて実行される。

### AskUserQuestion メニュー表示中の誤確定事故
2026-07-26、#494/#466 の並行 worktree 運用(worker 2体 + 司令塔)で、作業者への追加指示のつもりで送った `send-text` + Enter が、表示中だった AskUserQuestion メニューの選択肢1「GPG エージェントをリセットして再試行」を誤確定させた。作業者が `gpgconf --kill gpg-agent` を実行し、ユーザーが直前に温めたパスフレーズキャッシュが消える実害が出た(#498)。手順5(1)の Constraint の通り、送信前に必ず `herdr agent read` で pane の状態を確認し、メニュー表示中は send-text を使わない(選択肢の Enter 確定のみで応答するか、メニューの解除を待つ)。

### send-keys Enter が chat 入力を submit できないことがある
2026-07-26、#494/#466 の並行運用で、pane の入力欄にテキストが置かれたまま `pane send-keys <pane-id> Enter` が繰り返し効かず、作業者が再開できなくなった(同じ pane でメニューの選択肢確定には Enter が効いていたため、原因切り分けに時間を要した)。これは上記「send-text は単体では実行されない」(send-text だけでは実行されず別途 Enter が要る、という話)とは別の話 — real Enter を送っても Claude Code の chat 入力側で submit されないケースがある、という話。

当時の回避策(`herdr pane run <pane-id> ""` で空文字+real Enter を送り pending テキストを submit する)は herdr 0.7.5 では効かないケースが確認されている(2026-07-30、#520)。0.7.5 で新設された `herdr agent prompt <agent-name> "<text>"` は、入力欄に既存の pending テキストが残っていてもそれを新テキストで**置換する**ところまでは実機確認できているが、この罠自体を踏まない上位互換の解ではない — **置換はされても submit されないケース**が確認されている(2026-07-31、#528。並行 worktree 運用の同一セッション内で4回再現。宛先 worker の状態は done / idle の両方で発生。いずれも `herdr pane send-keys <pane-id> Enter` の追撃で submit され復旧した)。herdr 0.7.5 はこのケースでもコマンドが `agent_prompted` を正常に返すため、戻り値だけでは失敗を検知できない。手順5(1)の標準手順は `agent prompt` 送信後に `herdr agent get <agent-name>` で working 遷移を確認し、遷移していなければ `herdr agent read` でメニュー非表示を確認のうえ `herdr pane send-keys <pane-id> Enter` で追撃する防御的手順とセットで運用する(詳細はそちらを参照)。`--wait` / `--until <STATUS>`(繰り返し指定可)/ `--timeout <MS>` を併用すれば送信と応答待ちを1コマンドに畳められる。

なお AskUserQuestion メニューの選択肢確定(ハイライト行の Enter)は、この submit 不全とは別の経路のため、従来どおり `pane send-keys <pane-id> Enter` で機能する。効かないのはあくまで chat 入力の submit。

2026-08-07 の /wt 運用(#570 → PR #571)で、この submit 不全が **worker→司令塔方向でも発生する**ことを初観測した。worker が完了時に送った【報告】push(`herdr agent prompt "commander-<repo名>" "..."`)が司令塔 pane の chat 入力欄に置かれたまま submit されず滞留し、ユーザーが滞留テキストに気づいて手動 Enter で送達して初めて司令塔セッションに user message として届いた。これまでの再現(#528 の4回 + 2026-07-31 の実踏)はすべて司令塔→worker方向であり、双方向で起きることが今回初めて確認された(詳細: #572)。

push の不達を前提に主チャネル(手順5(2)の `agent wait` + `agent read` によるプル型検知)で検知する既存設計は変更しない — 今回も司令塔はプル型で先に完了を検知・処理しており、push 不達による実害はなかった。

ユーザー向け救済手順: 司令塔 pane の chat 入力欄に滞留テキスト(【相談】【報告】プレフィックス付き)を見つけたら、手動 Enter で送達できる。司令塔がターン処理中の場合、送達したテキストはキューに入り、ターン終了後に届く(正常系)。

### agent prompt がユーザー由来の pending テキストを置換で消しうる
2026-08-12 の /wt 運用(Issue #553 → PR #579、worker 3 体 + 司令塔の並行運用)で、司令塔が Copilot レビュー差し戻し指示を `herdr agent prompt` で worker へ送った際、宛先 worker pane の chat 入力欄にユーザーが手で打った未送信テキスト(「PR #579の内容とレビュー結果を確認して」)が残っており、`agent prompt` の置換仕様(#520/#528 で実機確認済み。上記「send-keys Enter が chat 入力を submit できないことがある」参照)により消えた(#580)。消えたテキストは司令塔の差し戻し指示と実質重複していたため実害はなかったが、構造としては**ユーザーの未送信入力を司令塔が無断で消しうる**。同一セッション内で別 worker pane にもユーザー由来と思われる未送信テキスト(「PR #578のCI結果を確認して」)が置かれているのを観測しており、ユーザーが worker pane に直接入力する運用は一回きりではない。送信前の `herdr agent read` はメニュー誤確定の防止(#498)だけでなく、pending テキストの保全のためにも行う(手順5(1)の Constraint 参照。関連: #572)。

### GPG 署名コミットは worker pane から pinentry を出せない
worker pane は tty を持たず(`GPG_TTY` も stale)、pinentry を表示できない構造がある。gpg-agent のパスフレーズキャッシュ(このリポジトリは TTL 8h)は agent プロセスのメモリ内にあり、`gpgconf --kill gpg-agent` や agent の再起動を行うと TTL に関係なく消える。運用(実機確認済み、2026-07-26、#494/#466、#498): ユーザーが自分の生きている端末で1回署名(例: `echo test | gpg --clearsign -o /dev/null`)してキャッシュを温めれば、同一セッションの全 worker のコミットが通るようになる。司令塔は `gpg-connect-agent 'keyinfo --list' /bye` の出力の cached フラグ(`1`)でキャッシュの有無を確認できる。署名コミットで詰まった場合、worker に `gpgconf --kill gpg-agent` 等でエージェントを殺させず、ユーザーに1回解除(署名)を依頼する。

この詰まりは委任前の事前チェックで予防できる。詳細は手順4「GPG パスフレーズキャッシュの事前チェック」参照。

### keygrip 特定の awk が [E] サブキーを拾ってキャッシュを誤判定する
2026-08-31、GVA-NyaN の /wt 運用で、司令塔が GPG パスフレーズキャッシュの事前チェック(手順4)を実装した際、keygrip 特定の awk が「最初の ssb 行」の Keygrip を拾う形になっていた(#583)。鍵構成が `ssb [E]`(暗号化)→ `ssb [S]`(署名)の順だったため [E] サブキーの keygrip でキャッシュを照会してしまい、実際には温まっていた署名キャッシュを「冷えている(`-`)」と誤判定して、ユーザーに不要なキャッシュ温めを依頼した。SOP の散文(「[S] フラグ付き ssb 行の直後の Keygrip を読む」)は正しく、司令塔が都度書いた awk が仕様を満たしていなかった。[E] が先に並ぶのは gpg の既定出力順で、ssb が複数ある鍵構成では誰でも踏みうる。

```bash
# NG: 最初の ssb の keygrip を拾う([S] 判定がない)
awk '/^ssb/{s=1} s && /Keygrip/{print $3; exit}'

# OK: [S] フラグ付き ssb の直後の keygrip を拾う(手順4のワンライナー)
awk '/^ssb/ && /\[S\]/ {found=1; next} found && /Keygrip/ {gsub(/ /,"",$0); sub(/Keygrip=/,""); print; exit}'
```

OK 例は 2026-08-31 に WSL2 + ed25519 primary [SC] / cv25519 ssb [E] / ed25519 ssb [S] 構成で、[S] サブキーの keygrip を正しく選択し cached=`1` を返すことを確認済み(2026-09-28 に Arch Linux の同構成でも再確認)。awk を都度手書きせず、手順4のワンライナーをそのまま使う。なお OK 例の awk も、`user.signingkey` 未設定や [S] サブキーの無い鍵構成では空文字を返す。空のまま `grep` に渡すと全 KEYINFO 行にマッチしてしまうため、手順4のワンライナーの空チェック(`[ -n "$KEYGRIP" ] ||` ガード)とセットで使う。

### pane-id は非永続
pane-id はセッション中に compact されうる非永続 ID(詳細は `.config/claude/skills/herdr/SKILL.md` 参照)。

### wait の即時解決
gotcha(実機確認済み): `herdr agent wait` は対象が既に指定ステータスだと即座に解決する。作業者がまだ `working` に遷移していない段階で `idle` 待ちを仕掛けると、起動直後の未初期化状態を完了と誤検知しかねない。

### herdr agent wait の done 受理(0.7.5)
`done` は「人間がまだ見ていない完了」を表す UI 向けの状態。かつては `herdr agent wait` に `done` を渡すとエラーになっていた(実機確認済みのエラーメッセージ: `done is a UI attention state; use idle for CLI agent completion waits`)。herdr 0.7.5 では `--status` オプション自体が廃止されて `--until <STATUS>`(繰り返し指定可)に変わり、`done` も `--until done` および `--until` 省略時のデフォルトの両方で受理されるようになった(2026-07-30、#520 で実機確認)。手順5(2)は `idle` / `done` / `blocked` のいずれかにマッチするデフォルト待ちを前提にしている。

### 旧 agent wait 構文の移行漏れが「blocked 誤判定」として表面化した
2026-07-30、#520 の運用で `--status blocked` / `--status idle` を2本バックグラウンドで張る旧構文のまま監視を仕掛けたところ、`--status` が `unknown option` で即座に両方とも失敗終了し、`wait -n` がその即死を「先に終了した方」として即解決、`kill -0` 判別ロジックが `FIRED_STATUS=blocked` と誤判定した。作業者自体は新構文で正常に稼働していたため、監視側だけが空振りして誤った状態を報告するという紛らわしい形で表面化した。CLI 側の破壊的変更を SOP が追随できていないことの検知パターンとして記録しておく — 監視が異常終了せず不自然に即決着した場合は、CLI のオプション互換性を疑う。

### BLOCKED は複合ステータス
2026-07-05 の運用で、PR #348/#350 の `mergeStateStatus: BLOCKED` を「CI待ち」と解釈し、監視スクリプトが90分待機した(#355)。実際のブロック要因は Copilot レビューの未解決 conversation で、このリポジトリのブランチ保護では conversation 未解決はマージ不可。`BLOCKED` は CI実行中と conversation 未解決を区別できない複合ステータスのため、検知時は必ず GraphQL で reviewThreads の未解決数を確認する。

### push 直後の CLEAN は仮 CLEAN
「`mergeStateStatus=CLEAN` を確認 → `gh pr merge` 実行」の間に Copilot の自動レビューが非同期で着弾し、「base branch policy prohibits the merge」(conversation 未解決)でマージが拒否される TOCTOU(Time-of-check to time-of-use)が繰り返し発生している。共通パターンは、(1) 新コミット push または `gh pr update-branch` → (2) required checks 通過で `CLEAN` を確認 → (3) この時点で Copilot の(再)レビューはまだ実行中(push から着弾まで1〜2分の遅延がある)→ (4) マージ実行が policy 拒否 → (5) 再取得すると `BLOCKED` かつ未解決 reviewThreads が増えている、というもの。

- 2026-07-08、PR #384 と PR #387 で同日2回発生(#388)。PR #387 では「CLEAN 確認後に15秒待って reviewThreads を再チェック」を試したが、レビュー着弾がそれより遅く防げなかった
- 2026-08-01、PR #540 / #541 で PR 作成直後に `CLEAN`・未解決 thread 0件を確認してマージしたところ policy 拒否、再取得で `BLOCKED` + Copilot の未解決 thread 各1件が判明した(#542)

教訓: push から数分以内の `CLEAN` は「レビュー未着弾の仮 CLEAN」でありうる。`CLEAN` は判定時点のスナップショットにすぎないため、マージ直前に再取得し、push から十分(2分以上)待ってから reviewThreads を最終チェックする。policy 拒否はエラーではなく「conversation が割り込んだ」シグナルとして扱う(手順6 の Constraints 参照)。

### SendMessage は司令塔に届かない(構造的理由)
2026-07-04、copilot-quorum #303 の作業者が完了報告のため `SendMessage` を試行し、`You are the main conversation` エラーで失敗した(#341)。Claude Code のセッション間に直接チャネルはなく、作業者は自セッションの main のため司令塔という宛先が存在しない。上り報告は `SendMessage` ではなく、会話内テキスト出力(司令塔が `herdr agent read` で回収するプル型)と、herdr 経由の push(手順5「(3) 上り=内容」参照)の組み合わせで行う。

herdr が使えない環境(worktree だけで完結させたい等)では、作業者が report ファイルをスクラッチパッドに書き、司令塔が Monitor 等でポーリングするファイルベースのフォールバックも考えられる(#341 案C)。ただしポーリングコストがあり、herdr が使える環境では手順5「(3) 上り=内容」の下位互換にとどまるため、標準経路には採用していない。

### 相談待ち idle と完了 idle の判別
作業者は【相談】送信後も司令塔からの回答を待つ間 `idle` に遷移するため、`herdr agent wait` の `idle` 発火だけでは完了と断定できない(#394)。判別・応答の手順は手順5「(2) 上り=イベント」の「相談 idle の判別」参照。

### sleep 主体フェーズで idle が完了前に一時発火する
2026-07-12 の copilot-quorum 運用(PR #321 の作業者)で、作業者が headless TUI の実機検証で `sleep 3`〜`sleep 20` を挟むポーリングをしていた間、`idle` 発火 → `herdr agent read` で確認すると spinner 稼働中(作業継続中)、というフラップが 2 回続き、都度 wait を仕掛け直した(#428)。ステータスは idle→done→working を行き来した。上記「相談待ち idle と完了 idle の判別」の二分岐だけだと、この作業途中の一時 `idle` を完了と誤認するリスクがある。`idle` 発火時の recent ログ確認では、【相談】の有無・完了報告の有無に加えて spinner の稼働と最終報告の有無も見て「作業続行中のフラップ」を判別し、`working` 遷移を待ってから wait を仕掛け直す(手順5「(2) 上り=イベント」の「相談 idle の判別」参照)。

### レビュー差し戻しラウンドによる worker context の逼迫
本業リポジトリの PR(2026-07-27)で、差し戻し2ラウンド後に worker が context 60% に到達し、ユーザーが先に検知した。差し戻しは元実装の全文脈を保持した worker に送るのが品質上望ましい一方、ラウンドごとに context は単調に増える。50% を目安に「直接対応 or 引き継ぎ」へ切り替える(上記手順5(1) の Constraint)。ステータスラインの使用率は `herdr agent get <agent-name>` で pane-id を引いてから `herdr pane read <pane-id> --source visible` を実行し、その末尾行で機械的に読める(ただし pane 幅が狭いと切り詰められて読めないケースがある。詳細と代替手段は次項「ステータスライン切り詰めで 💭 が読めない」参照)。

### ステータスライン切り詰めで 💭 が読めない
2026-07-31、上記の運用で `herdr pane read <pane-id> --source visible` の末尾ステータスラインが pane 幅で切り詰められ(`⚡ Sonnet 5  xhigh …` までで省略)、💭 の値が読めないケースが発生した(#529)。ステータスラインの表示順で 💭 が右寄りにあるため、pane が狭いと機械的に読めない。

調査の結果(実機確認済み)、herdr CLI に pane 幅非依存で context 使用率を取得できる経路は見つからなかった:
- `herdr agent get <agent-name>` の JSON 出力(`agent`/`agent_status`/`cwd`/`pane_id`/`workspace_id` 等) に context 使用率相当のフィールドは無い
- `herdr pane read <pane-id>` の `--source visible/recent/recent-unwrapped/detection` を総当たりしても、`recent-unwrapped`(改行の折り返し解除)や `--raw`、`--format text/ansi` を組み合わせても 💭 の省略記号(`…`)は変わらない。Claude Code 側の TUI がステータスラインを pane の列数に応じて描画時点で切り詰めており、pane 幅そのものを変えない限り herdr 側の出力オプションでは回避できない
- `herdr api snapshot` にはペイン分割レイアウトの `ratio`(split の分割比率であり context 使用率とは無関係)はあるが、context/token/usage 相当のフィールドは無い
- `herdr agent explain` は working/idle 等の検知根拠のみ、`herdr pane process-info` は前面プロセスの argv/cwd のみで、いずれも context 情報は含まない

そのため、切り詰められて読めない場合は保守的に (a) 直接対応 または (b) 引き継ぎ 側へ倒す(上記手順5(1) の Constraint)。pane を広げれば読める可能性はあるが、他 worker の pane レイアウトを都合で変更するのは対話プロトコル上望ましくないため、標準手順としては採用しない。根本解決には statusline の表示順変更(💭 を左寄りにする等、`.config/claude/statusline` 系の変更)が必要だが、この skill のスコープを超えるため別途 Issue 化を検討する。

### commander-<repo名> の名前衝突
同リポジトリの過去セッション pane が名前を保持していると `herdr agent rename` が
`agent_name_taken` で失敗する。他 pane の rename は禁止(MUST NOT)のため、
`commander-<repo名>-2` のように数字サフィックス(またはタスク由来の意味サフィックス)を付けて自分を命名し、
**作業指示プロンプト内の宛先(【相談】【報告】の push 2箇所と、相談の無応答フォールバックの `herdr agent get` の計3箇所)も同じ名前に揃える**こと。
サフィックス付き名でも上り報告プロトコルはそのまま機能する(実機確認済み)。

3件の実例で再発しており、衝突は1回きりの偶発事象ではなく再発する運用パターンであることを示す:
- 2026-07-12 copilot-quorum: `commander-copilot-quorum` → `-2`
- 2026-07-18 dotfiles: `commander-dotfiles` → `-2` → `-3`(サフィックスが2つ埋まっている状態での発生)
- 2026-07-20 dotfiles: `commander-dotfiles` → 意味サフィックス `-dpp`。このケースでは保持者(pane `w3C:p2`)が過去セッションの残骸ではなく、**同リポジトリで別タスクを進行中の同時稼働 live セッション**だったことが判明した。この種の衝突は正当な同時運用が原因のため、stale 名の掃除では解決せず、サフィックス命名規定そのものが本質的な対応になる(意味サフィックスは複数司令塔が並行稼働時にどれがどれか識別しやすい利点がある)

### 非ASCII・不可視文字(PUA グリフ等)をファイルに書く場合
Nerd Font の PUA グリフ等をツール呼び出しで直接タイプすると、バイト列が消失して空文字列になったり、意図せず `\uXXXX` テキストに化けたりする(不可視文字はエディタ・diff・レビューUIのどこでも見えず、目視でのミス検出ができない構造的な罠 — #363、PR #366)。該当する書き込みは以下の手順で行う: JSON ファイルへは、コードポイントが BMP 内(U+FFFF 以下)なら `\uXXXX` エスケープをリテラル ASCII 文字列として書いてよいが、U+10000 以上(サロゲートペアが必要。Nerd Fonts 由来の記号で頻出、例: `U+F0A1E`)では `\uXXXX` 単体では表現できず手順が破綻するため、`python3 -c "import json; print(json.dumps('<文字>', ensure_ascii=True))"` 等でサロゲートペアのエスケープを機械生成して貼る。JSON 以外のファイルは Python の `chr()` でコードポイントから機械的に文字列を組み立ててファイル I/O で書き込む。書き込み後は hex dump(`xxd` 等)で機械的に検証する(目視確認は禁止)。コードポイントの正典は `ryanoasis/nerd-fonts` リポジトリの `glyphnames.json`。

### push 直後の `gh pr checks --watch` が即失敗する
2026-09-23、GVA-NyaN の並行 worktree 運用(PR #179 / #180)で、force-push・push の直後に仕掛けた `gh pr checks <n> --watch` が「no checks reported」で exit 1 になり、CI 監視が空振りした(worker 2 体で同時に発生)。GitHub 側の check 登録に数秒〜十数秒のラグがあるため。対処は「15〜20 秒待ってから再実行」で、失敗扱いにしない。`sleep N && gh pr checks` に逃げるとハーネスに blocked されうるので、待ちは run_in_background の watch の再武装で行う。

### dynamic workflow のオプトインキーワードが作業指示経由で誤発火する
Claude Code は、ユーザープロンプト中に `ultra` と `code` を連結した1語のキーワードを見つけると、multi-agent orchestration(dynamic workflow)へのオプトインとして扱う(Claude Code 2.1.160 で旧キーワードから改名)。作業指示プロンプト経由で worker に渡った文字列も「ユーザープロンプト」として発火するため、worker が意図しない「Run a dynamic workflow?」ダイアログで `blocked` になる。2026-07-24、claude:effort のこのキーワード対応(#487 / PR #488)を委任した際に実発生し、worker は司令塔の介入指示で workflow を辞退して逐次実装に切り替えた(成果物への影響なし、#489)。司令塔は代理承認できない(手順4)ため、発火のたびに人間へのエスカレーションが必要になる。

教訓:
- 作業指示プロンプトにこのキーワードを連結形のまま書かない。「`ultra` と `code` を連結したキーワード」のように分割して書くか、「dynamic workflow のオプトインキーワード(#489 参照)」のように間接表記する。キーワード自体を扱うタスクでも同様で、コミットメッセージ・PR タイトル・PR 本文にも連結形を書かないよう作業指示に明記する
- この SOP 自体もスキル起動時にセッションへ読み込まれるため、SKILL.md に連結形を書くと /wt を使うたびに誤発火しうる。この節も含め、SOP への追記では連結形を使わない
- 発火した場合の標準対処: `herdr agent read` でダイアログ表示を確認し、人間の判断で辞退(No)する場合は `herdr pane send-keys <pane-id> 3` でダイアログを辞退してから、逐次実装で進める旨の補足指示を送る(送信手順は手順5(1) の標準手順に従う)
