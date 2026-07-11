---
name: wt
description: "タスクの説明からブランチ名を自動生成し、herdr の worktree + workspace を立ち上げ、必要なら作業担当エージェントに委任する。ユーザーが新しい作業を始めたい・worktree を切りたい・「/wt」と言った時に使う。"
---

# Worktree 作成 (herdr)

## Overview

タスクの説明からブランチ名を自動生成し、herdr の worktree + workspace を立ち上げます。

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
- **MUST**: 冪等に実行する(rename が herdr デーモン再起動を跨いで保持されるかは未確認のため、それに依存せず毎回再宣言する設計とする)
- **MUST NOT**: `herdr agent rename` は司令塔が自分自身(`$HERDR_PANE_ID`)に対してのみ実行する。作業者や他ペインの名前を司令塔側から書き換えない

```bash
herdr worktree create --cwd <repo-root> --branch <branch-name> --base main --focus
```

**Constraints:**
- **MUST**: worktree 作成前に `git fetch origin && git merge --ff-only origin/main` でローカル main を最新化する(特にマージ直後に続けて次の worktree を切る連続運用で必須。詳細: `/wtclean` Troubleshooting「git branch -d の not yet merged to HEAD 警告」参照)
- **MUST**: ベースブランチはデフォルト `main`。ユーザーが入力内で別のベースを指定した場合はそれに従う
- **MUST**: 作成結果(worktree のパス、workspace ID)をユーザーに報告する

#### worktree の準備

worktree 作成直後に以下を行う:

**Constraints:**
- **MUST**: `mise trust <worktree-path>` を実行する(詳細: Troubleshooting「mise trust 忘れ」参照)
- **MUST**: allowlist を配置する: `mkdir -p <worktree-path>/.claude && cp ~/.claude/templates/wt-settings.local.json <worktree-path>/.claude/settings.local.json`
  - コピー元は `<repo-root>/.config/claude/templates/...` ではなく `~/.claude/templates/...` を使う。`<repo-root>` は `/wt` を呼び出した対象リポジトリ次第で変わり、dotfiles 以外のリポジトリではこのテンプレートを含まないため
  - `~/.claude` への反映は home-manager 経由(`home.nix` の `home.file ".claude".source = ./.config/claude`)で、`mise run nix:switch` 実行時に `/nix/store` スナップショットへの per-file symlink が生成される方式。テンプレートを追加・変更したら `mise run nix:switch` を実行しないと `~/.claude/templates/` に反映されない(詳細: Troubleshooting「allowlist テンプレートの cp 失敗」参照)
  - 定型で安全な操作(`git`・`gh`・`mise`・`herdr` の一部サブコマンド、司令塔がタスク指示を置くスクラッチパッドの読み取り)を宣言的に許可し、作業者の permission 往復(A類)を設計で消す。詳細は allowlist テンプレート本体を参照

### 4. エージェントの起動(任意)

タスク内容が具体的な場合、新しい workspace でエージェントを起動してタスクを渡す:

```bash
herdr agent start claude-<branch-name 由来のユニーク名> --workspace <workspace-id> --cwd <worktree-path> --split down --focus -- claude --model claude-sonnet-5 --effort <effort> --permission-mode auto "$(cat <<'PROMPT'
<作業指示プロンプト（複数行可）>
PROMPT
)"
```

**Constraints:**
- **MUST**: `--cwd` は必須。省略すると呼び出し元シェルの cwd(リポジトリ本体)を引き継ぎ、worktree 外で作業が始まってしまう
- **MUST**: `--split down` で pane を上下分割にする(省略時はデフォルトの `right` で左右分割になってしまう)
- **MUST**: エージェント名はセッション全体でユニーク制約があるため、固定名 `claude` ではなくブランチ名由来の名前にする。変換ルール: ブランチ名から prefix(`fix/` 等)を除き、`_` と `/` を `-` に置換して `claude-` を前置する(例: `fix/wt_agent_start_options` → `claude-wt-agent-start-options`)
- **MUST**: 作業者モデルはデフォルト `claude-sonnet-5`(司令塔=メインセッションが計画とレビュー、作業者が実装を担う分業)。ユーザーが入力内で別モデルを指定した場合はそれに従う
- **MUST**: `--permission-mode auto` で起動する。定型操作は自動承認され、判断が必要な操作だけが blocked として表面化する
- **MUST NOT**: `--dangerously-skip-permissions` は使わない(監督を全て外すのではなく、エスカレーションのレーンを残すのが目的)
- **MUST**: それでも blocked が発生した場合、司令塔は代理承認できない(Claude Code が禁止している)。司令塔の責務は「即検知して人間に知らせる」まで(#332 の対話プロトコル参照)
- **MUST**: auto mode 起動がハーネス(auto mode 分類器)に拒否された場合、AskUserQuestion 等でユーザーに auto mode 起動の許可を明示的に確認してから再実行する(詳細: Troubleshooting「auto mode 起動の拒否」参照)
- **MUST NOT**: タスクが曖昧な場合は起動しない。**MUST**: その場合は workspace の準備完了だけ報告して終わる

#### effort の選択基準

司令塔がタスクの難易度を見て判断する:

| effort | 使いどころ |
|--------|-----------|
| medium | 定型・機械的な変更(バージョン bump、typo 修正、設定1行の変更) |
| high | 通常の実装タスク(迷ったらこれ。Sonnet 5 のデフォルト) |
| xhigh | 難しい実装・複数ファイルにまたがる変更・設計判断を含むタスク |

**Constraints:**
- **MUST NOT**: `low` は /wt では使わない(under-thinking のリスクがあるため)
- **SHOULD**: `medium` 以下では Sonnet 5 が指示を literal に解釈するため、作業指示プロンプトの完了条件を具体的に書く

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

## 相談
実装の方向を左右する判断で確信が持てないときは、最終報告まで抱え込まず、その場で司令塔へ相談を push する。判断に迷う点のうち、実装の方向を左右しない小さなものは上記「## 制約」の通り最終報告に書けばよい。

エスカレーションすべき判断の例:
- 複数の妥当な実装方式があり、どれを選ぶかで挙動やインターフェースが変わる
- Issue や指示の内容と、現状のコードベースの実態が食い違っている
- 破壊的変更(既存の挙動・データ・API 等を壊しうる変更)を伴う判断

**丸投げ禁止**: 相談には必ず「選択肢(A/B...) + 自分の推奨」をセットで送る。判断材料を示さず「どうしましょう」とだけ聞かない。

```bash
COMMANDER_PANE=$(herdr agent get commander-<repo名> | jq -r .result.agent.pane_id)
herdr pane send-text "$COMMANDER_PANE" "【相談】<branch>: <選択肢A/B + 自分の推奨>"
herdr pane send-keys "$COMMANDER_PANE" Enter
```

相談を送ったら、司令塔からの回答(pane に届く追加指示)を待つ。回答が届くまで、相談した論点については実装を進めない。

- `commander-<repo名>` が見つからない等、push が失敗した場合はエラーで止まらない。返答を待ち続けると作業が止まってしまうため、その場で自分の推奨案を採用して実装を進め、判断の経緯を最終報告に書く(push はあくまで即時性のための冗長化で、必須経路ではない)

## 報告
報告の正はこの会話へのテキスト出力(司令塔が `herdr agent read` で回収する)。**`SendMessage` は使わない** — 作業者は自セッションの main のため司令塔という宛先が存在せず、`You are the main conversation` エラーになる。

完了したら、変更ファイル・PR の URL・確認した動作を簡潔にまとめてこの会話に書く。指示外の気づき（環境の摩擦・想定外の挙動・自分で編み出した回避策）があれば、解決済みであっても必ず報告する（該当なしなら「なし」と明記する）。

会話内報告に加えて、完了時に司令塔へ1行の push 報告を送る(フォーマット: `【報告】<branch>: <一行サマリ>（<PR URL>）`。詳細は上記の会話内報告に書き、push は要約1行のみでよい):

```bash
COMMANDER_PANE=$(herdr agent get commander-<repo名> | jq -r .result.agent.pane_id)
herdr pane send-text "$COMMANDER_PANE" "【報告】<branch>: <一行サマリ>（<PR URL>）"
herdr pane send-keys "$COMMANDER_PANE" Enter
```

- `commander-<repo名>` が見つからない等、push が失敗した場合はエラーで止まらず、会話内報告のみに縮退して続行する(push はあくまで即時性のための冗長化で、必須経路ではない)
````

**Constraints:**
- **SHOULD**: 背景と完了条件を具体的に書く(書くほど作業品質が安定する)

### 5. 対話プロトコル(委任後の監視と対話)

エージェント起動後、司令塔(このセッション)と作業者エージェントの間のやり取りは、以下の4本柱からなる対話プロトコルとして運用する(設計の背景は #332、上り=内容の push 設計は #341 参照)。(4) 供養 は `/wtclean` 側で扱う。

#### (1) 下り=指示

委任時の指示は手順4の heredoc テンプレートで渡す。委任後に追加の指示を送りたい場合は、pane へのテキスト送信と Enter 送信を分けた2段で行う。作業者からの【相談】(手順4テンプレート「## 相談」参照)への回答もこの手順で送る(詳細な判別・応答フローは下記(2)「相談 idle の判別」参照):

```bash
herdr pane send-text <pane-id> "<追加指示のテキスト>"
herdr pane send-keys <pane-id> Enter
```

**Constraints:**
- **MUST**: pane へのテキスト送信と Enter 送信を分けた2段で行う(詳細: Troubleshooting「send-text は単体では実行されない」参照)
- **MUST**: `<pane-id>` は対象エージェント名から `herdr agent list` で引く(`pane_id` フィールド)
- **MUST**: 実行前に対象の pane-id / agent 名を必ず確認する(宛先を誤ると、無関係な pane やこの司令塔自身の入力欄にテキストが挿入されてしまう。`agent send` / `pane send-text` はテキストを引数としてそのまま送るだけで、確認や取り消しは挟まらない)
- **MUST**: 長時間の監視をまたぐ場合は都度 `herdr agent list` で引き直し、古い pane-id を使い回さない(詳細: Troubleshooting「pane-id は非永続」参照)

#### (2) 上り=イベント

委任直後、作業者の状態が `working` に遷移したことを確認してから、`blocked`(詰まり)と `idle`(完了)の2状態を同時にバックグラウンドで待ち受ける(詳細: Troubleshooting「wait の即時解決」参照):

```bash
# gotcha: 対象が既に指定ステータスだと即座に解決してしまうため、working に遷移済みか確認してから仕掛ける
AGENT_NAME=<agent-name>
herdr agent get "$AGENT_NAME"

herdr agent wait "$AGENT_NAME" --status blocked > "/tmp/wait-blocked-${AGENT_NAME}.json" 2>&1 &
BLOCKED_PID=$!
herdr agent wait "$AGENT_NAME" --status idle > "/tmp/wait-idle-${AGENT_NAME}.json" 2>&1 &
IDLE_PID=$!

wait -n "$BLOCKED_PID" "$IDLE_PID"

# 生き残っている方が「発火しなかった側」。kill -0 で存否確認してから判別する
if kill -0 "$BLOCKED_PID" 2>/dev/null; then
  FIRED_STATUS=idle
  kill "$BLOCKED_PID" 2>/dev/null
else
  FIRED_STATUS=blocked
  kill "$IDLE_PID" 2>/dev/null
fi
```

**Constraints:**
- **MUST**: ログファイル名には `<agent-name>` を含める。複数 worktree を並行監視しているときに固定ファイル名だと内容が上書きされてしまうため
- **MUST**: `wait -n` は先に終了した方を検知する。ただし `wait -n` 自身はどちらが終了したかを返さないため、直後に `kill -0 "$BLOCKED_PID"`(シグナルを送らず存否だけ確認する)で生死を見て、生きている方=発火しなかった方、と判別してから後処理する。判別できたら `$FIRED_STATUS` を見て、`blocked` ならユーザーに承認を仰ぎ、`idle` なら `herdr agent read "$AGENT_NAME" --source recent --lines 50` で完了報告を確認する
- **MUST**: `<agent-name>` は手順4でエージェントに付けたユニーク名。`herdr agent wait` / `herdr agent read` は pane-id ではなく agent 名を直接ターゲットにできるため、監視中に pane-id を引き直す必要がない
- **MUST NOT**: 定期ポーリング(`herdr pane list` 等を一定間隔で呼び続けるループ)は禁止。コストが高いうえ、このプロトコルが解消したいアンチパターンそのもの
- **MUST NOT**: `--status done` は使わない(詳細: Troubleshooting「herdr agent wait は done を拒否する」参照)
- **MUST**: 似た用途で `herdr wait agent-status <pane-id> --status <...|done|...>` というコマンドもあるが、こちらは pane-id が必須かつ `done` を受け付ける UI 向けのコマンド。CLI 主導のこのプロトコルでは agent 名を直接使える `herdr agent wait <agent-name>` を使う
- **MAY**: `--timeout`(ミリ秒)は省略可能で、省略すると無期限にブロックする。バックグラウンドで放置する分には問題ないが、安全弁として妥当な値を指定してもよい
- **MUST**: タイムアウトした場合は同じ2つの wait を仕掛け直す(これは定期ポーリングではなく、イベント待ちの再武装)

**相談 idle の判別:**

作業者は【相談】送信後も司令塔からの回答を待つ間 `idle` に遷移する(手順4テンプレート「## 相談」参照)。そのため `idle` 発火は「完了」と「相談待ち」のどちらもありうる。

- **MUST**: `idle` 発火時は完了と断定せず、`herdr agent read "$AGENT_NAME" --source recent --lines 50` で直近ログを確認する。末尾付近に `【相談】` があれば「相談待ちの idle」、なければ「完了の idle」と判定する
- **MUST**: 「相談待ちの idle」と判定したら、上記(1)「下り=指示」の手順(pane send-text + send-keys Enter の2段)で回答を返す。回答後は作業者が再び `working` に遷移したことを確認したうえで、`blocked`/`idle` の2状態待ちを仕掛け直す(詳細: Troubleshooting「相談待ち idle と完了 idle の判別」参照)

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
| CLEAN | マージしてよい(実行はユーザー承認のもとで) |
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
- **MUST NOT**: `mergeStateStatus` が `CLEAN` になる前にマージを実行しない

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

### ライブセッション検証時の誤 kill 事故
2026-07-05、作業者エージェントが検証用に起動したはずの Alacritty が実際にはマップされておらず、直後に `pgrep -af alacritty` で拾った PID をテスト用ウィンドウと誤認して kill し、ユーザーが元から開いていた既存の Alacritty(workspace 2)を誤終了させた(#354、PR #353)。自分が起動したプロセスは起動時の `$!` で PID を捕捉して追跡し、事後に名前ベースの `pgrep` で「自分のものらしきプロセス」を探して kill するのは禁止。

### send-text は単体では実行されない
`pane send-text` は pane の入力欄にテキストを挿入するだけで、送信(実行)はされない。実機確認済み: `send-text` の直後に `pane read` してもコマンドは未実行のまま入力欄に残っており、続けて `pane send-keys <pane-id> Enter` を送って初めて実行される。

### pane-id は非永続
pane-id はセッション中に compact されうる非永続 ID(詳細は `.config/claude/skills/herdr/SKILL.md` 参照)。

### wait の即時解決
gotcha(実機確認済み): `herdr agent wait` は対象が既に指定ステータスだと即座に解決する。作業者がまだ `working` に遷移していない段階で `idle` 待ちを仕掛けると、起動直後の未初期化状態を完了と誤検知しかねない。

### herdr agent wait は done を拒否する
`herdr agent wait` に `done` を渡すとエラーになる(実機確認済みのエラーメッセージ: `done is a UI attention state; use idle for CLI agent completion waits`)。`done` は「人間がまだ見ていない完了」を表す UI 向けの状態で、CLI から作業完了を検知するときは `idle` を使う。

### BLOCKED は複合ステータス
2026-07-05 の運用で、PR #348/#350 の `mergeStateStatus: BLOCKED` を「CI待ち」と解釈し、監視スクリプトが90分待機した(#355)。実際のブロック要因は Copilot レビューの未解決 conversation で、このリポジトリのブランチ保護では conversation 未解決はマージ不可。`BLOCKED` は CI実行中と conversation 未解決を区別できない複合ステータスのため、検知時は必ず GraphQL で reviewThreads の未解決数を確認する。

### SendMessage は司令塔に届かない(構造的理由)
2026-07-04、copilot-quorum #303 の作業者が完了報告のため `SendMessage` を試行し、`You are the main conversation` エラーで失敗した(#341)。Claude Code のセッション間に直接チャネルはなく、作業者は自セッションの main のため司令塔という宛先が存在しない。上り報告は `SendMessage` ではなく、会話内テキスト出力(司令塔が `herdr agent read` で回収するプル型)と、herdr 経由の push(手順5「(3) 上り=内容」参照)の組み合わせで行う。

herdr が使えない環境(worktree だけで完結させたい等)では、作業者が report ファイルをスクラッチパッドに書き、司令塔が Monitor 等でポーリングするファイルベースのフォールバックも考えられる(#341 案C)。ただしポーリングコストがあり、herdr が使える環境では手順5「(3) 上り=内容」の下位互換にとどまるため、標準経路には採用していない。

### 相談待ち idle と完了 idle の判別
作業者は【相談】送信後も司令塔からの回答を待つ間 `idle` に遷移するため、`herdr agent wait` の `idle` 発火だけでは完了と断定できない(#394)。判別・応答の手順は手順5「(2) 上り=イベント」の「相談 idle の判別」参照。

### 非ASCII・不可視文字(PUA グリフ等)をファイルに書く場合
Nerd Font の PUA グリフ等をツール呼び出しで直接タイプすると、バイト列が消失して空文字列になったり、意図せず `\uXXXX` テキストに化けたりする(不可視文字はエディタ・diff・レビューUIのどこでも見えず、目視でのミス検出ができない構造的な罠 — #363、PR #366)。該当する書き込みは以下の手順で行う: JSON ファイルへは、コードポイントが BMP 内(U+FFFF 以下)なら `\uXXXX` エスケープをリテラル ASCII 文字列として書いてよいが、U+10000 以上(サロゲートペアが必要。Nerd Fonts 由来の記号で頻出、例: `U+F0A1E`)では `\uXXXX` 単体では表現できず手順が破綻するため、`python3 -c "import json; print(json.dumps('<文字>', ensure_ascii=True))"` 等でサロゲートペアのエスケープを機械生成して貼る。JSON 以外のファイルは Python の `chr()` でコードポイントから機械的に文字列を組み立ててファイル I/O で書き込む。書き込み後は hex dump(`xxd` 等)で機械的に検証する(目視確認は禁止)。コードポイントの正典は `ryanoasis/nerd-fonts` リポジトリの `glyphnames.json`。
