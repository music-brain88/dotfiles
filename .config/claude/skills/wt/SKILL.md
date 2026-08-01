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
- **MUST**: 毎回再宣言を試みる。ただし rename は herdr デーモン再起動・セッション終了を跨いで pane に名前が残るため、過去セッションの pane が同名を保持していると単純な再宣言では冪等にならない(実例3件: #427)
- **MUST**: rename が `agent_name_taken` で失敗した場合、サフィックス付きの名前で空いているものまで採って再試行する。デフォルトは数字サフィックス(`commander-<repo名>-2`, `-3`...)。タスク由来の意味サフィックス(例: `commander-dotfiles-dpp`)も可 — 同一リポジトリで複数司令塔が同時稼働している場合、どの司令塔か人間が識別しやすくなる。要件はユニークであることのみ
- **MUST**: サフィックス付き名を採用した場合、以降そのセッションで使う「作業指示プロンプト」内の司令塔宛先(手順4テンプレートの `commander-<repo名>` 箇所すべて。【相談】【報告】の2箇所)を実際に採用した名前に統一する
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
  - 定型で安全な操作(`git`・`gh`・`mise`・`herdr` の一部サブコマンド、司令塔がタスク指示を置くスクラッチパッドの読み取り)を宣言的に許可し、作業者の permission 往復(A類)を設計で消す。詳細は allowlist テンプレート本体を参照

### 4. エージェントの起動(任意)

タスク内容が具体的な場合、新しい workspace でエージェントを起動してタスクを渡す。

#### GPG パスフレーズキャッシュの事前チェック

worker はコミット時に GPG 署名で詰まりやすい(worker pane は tty を持たず pinentry を表示できない構造的制約。詳細: Troubleshooting「GPG 署名コミットは worker pane から pinentry を出せない」参照)。委任前にキャッシュの有無を確認し、冷えていれば温めておく。

```bash
gpg-connect-agent 'keyinfo --list' /bye
```

**Constraints:**
- **MUST**: 署名鍵の keygrip は次の手順で特定する: `git config user.signingkey` で鍵IDを取得し、`gpg --list-secret-keys --with-keygrip` の出力から同じ鍵に属する `[S]` フラグ付きサブキー(ssb)行の直後にある `Keygrip` を読む(`user.signingkey` は primary 鍵の ID を指すが、実際の署名には `[S]` サブキーの keygrip が使われるため。実機確認済み)
- **MUST**: 上記 keygrip で `gpg-connect-agent 'keyinfo --list' /bye` の出力(`S KEYINFO <keygrip> D - - <cached> P - - -` 形式)をフィルタし、7列目が `1` かどうかでキャッシュの有無を確認する(実機確認済み)
- **SHOULD**: 冷えている(7列目が `1` でない)場合、ユーザーに1回署名(`echo test | gpg --clearsign -o /dev/null`)によるキャッシュ温めを依頼する
- **MAY**: 温めは委任と並行に進めてよいが、worker がコミットに到達する前に温まっているのが望ましい

#### pane の用意とエージェント起動

pane の用意とエージェント起動は分離された2段構成になっている。まず worktree 専用 workspace のルート pane(手順3で控えた `result.root_pane.pane_id`)から下に pane を割り、作業指示は司令塔自身のスクラッチパッドディレクトリにファイルとして書く(長文プロンプトを直接 inline できない理由は下記 Constraints 参照):

```bash
herdr pane split --pane <root-pane-id> --direction down --cwd <worktree-path>
```

新しい pane-id は応答 JSON の `result.pane.pane_id` から取得する。続けて作業指示をファイルに書き、エージェントを起動する:

```bash
cat > <司令塔のスクラッチパッドディレクトリ>/task-<branch-name>.md <<'PROMPT'
<作業指示プロンプト（複数行可）>
PROMPT

herdr agent start claude-<branch-name 由来のユニーク名> --kind claude --pane <new-pane-id> -- --model claude-sonnet-5 --effort <effort> --permission-mode auto "<司令塔のスクラッチパッドディレクトリ>/task-<branch-name>.md を読み、その内容全体をあなたへの作業指示として忠実に実行してください。"
```

**Constraints:**
- **MUST**: pane の用意は `herdr pane split` で行う。split 元の `--pane` には手順3の `result.root_pane.pane_id`(worktree 専用 workspace のルート pane)を使う。司令塔自身の pane(`$HERDR_PANE_ID`)を split 元にすると、worker pane が司令塔の workspace 側に作られてしまい、worker を worktree 専用 workspace に置く設計(旧構文の `--workspace` 指定が担っていた部分)が壊れる
- **MUST**: `--cwd` は必須。省略すると split 元 pane の cwd を引き継ぎ、worktree 外で作業が始まってしまう
- **MUST**: `pane split` の `--direction down` で pane を上下分割にする(省略時はデフォルトの `right` で左右分割になってしまう)
- **MUST NOT**: `herdr agent start` に `--workspace` / `--cwd` / `--split` / `--focus` を渡さない。herdr 0.7.5 で廃止され `unknown option` エラーになる。pane はあらかじめ `pane split` で用意し、`agent start` には `--pane <pane split で得た pane-id>` を渡す
- **MUST**: `--kind claude` が実行ファイルの正典を与えるため、`--` 以降には実行ファイル名(`claude`)を含めず、引数のみを渡す
- **MUST**: 作業指示プロンプトは `AGENT_ARG` に直接 inline しない。複数行 heredoc をそのまま渡すと `invalid_agent_argument: agent arguments cannot be encoded safely for the target shell` で拒否される(詳細: Troubleshooting「長文プロンプトの inline 渡しが拒否される」参照)。作業指示は司令塔自身のスクラッチパッドディレクトリにファイルとして書き、起動プロンプトは「<パス> を読み、その内容全体をあなたへの作業指示として忠実に実行してください。」の1行にする
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
- GPG 署名で詰まった場合、`gpgconf --kill gpg-agent` 等で gpg-agent を殺さない(キャッシュ破壊で他作業者を巻き込む)。署名の失敗は「## 相談」の手順で司令塔へエスカレーションする

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

相談を送ったら、司令塔からの回答(pane に届く追加指示)を待つ。回答が届くまで、相談した論点については実装を進めない。

- `commander-<repo名>` が見つからない等、push が失敗した場合はエラーで止まらない。返答を待ち続けると作業が止まってしまうため、その場で自分の推奨案を採用して実装を進め、判断の経緯を最終報告に書く(push はあくまで即時性のための冗長化で、必須経路ではない)

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
- **MUST**: テンプレート中の `commander-<repo名>`(【相談】【報告】2箇所)はプレースホルダ。司令塔が手順3で実際に名乗った名前(サフィックス付きの場合はそれを含む)に置き換えてから作業者に渡す

### 5. 対話プロトコル(委任後の監視と対話)

エージェント起動後、司令塔(このセッション)と作業者エージェントの間のやり取りは、以下の4本柱からなる対話プロトコルとして運用する(設計の背景は #332、上り=内容の push 設計は #341 参照)。(4) 供養 は `/wtclean` 側で扱う。

#### (1) 下り=指示

委任時の指示は手順4のファイル渡し方式(スクラッチパッドへのファイル書き込み+1行の起動プロンプト)で渡す。委任後に追加の指示を送りたい場合は、`herdr agent prompt <agent-name> "<追加指示のテキスト>"` の1コマンドで送る。agent 名を直接ターゲットにできるため pane-id の引き直しが不要になる。作業者からの【相談】(手順4テンプレート「## 相談」参照)への回答もこの手順で送る(詳細な判別・応答フローは下記(2)「相談 idle の判別」参照):

```bash
herdr agent prompt <agent-name> "<追加指示のテキスト>"
```

**Constraints:**
- **MUST**: `<agent-name>` は手順4でエージェントに付けたユニーク名をそのまま使う。pane-id の引き直しは不要
- **MUST**: 実行前に対象の agent 名を必ず確認する(宛先を誤ると、無関係なエージェントに指示が届いてしまう。`agent prompt` はテキストを引数としてそのまま送るだけで、確認や取り消しは挟まらない)
- **MUST**: 送信前に `herdr agent read` で対象 pane の状態を確認する。AskUserQuestion 等のメニューが表示中は `agent prompt` を使わない(chat 入力欄への送信になるため、ハイライトされている選択肢を誤確定させる罠がある。`send-text` + Enter でこの誤確定による実害が実際に出ており(詳細: Troubleshooting「AskUserQuestion メニュー表示中の誤確定事故」参照)、`agent prompt` も同じくメニュー表示中の pane に送信する以上、予防的に避ける)。メニューの選択肢確定自体は従来どおり `herdr pane send-keys <pane-id> Enter` で行う(pane-id は `herdr agent get <agent-name>` で都度引く。詳細: Troubleshooting「pane-id は非永続」参照)
- **MUST**: レビュー差し戻し等、委任後に追加の作業ラウンドを送る前に、`herdr agent get <agent-name>` で pane-id を引いたうえで `herdr pane read <pane-id> --source visible` を実行し、末尾行の pane 下部ステータスラインで context 使用率(💭 n%)を確認する。50% を超えている場合は追加ラウンドを送らず、(a) 司令塔が直接対応する、(b) 新 worker へ引き継ぐ(引き継ぎブリーフ = 元ブリーフ + ここまでの成果物参照(PR URL / コミット)+ 残作業のみ)、のいずれかを選ぶ。ユーザーより先に司令塔が検知すべきシグナルであり、閾値超過を検知したら対応方針とあわせてユーザーに報告する(詳細: Troubleshooting「レビュー差し戻しラウンドによる worker context の逼迫」参照)
- **MAY**: `--wait` / `--until <STATUS>`(繰り返し指定可)/ `--timeout <MS>` を併用すると、送信と応答待ちを1コマンドに畳められる(詳細: Troubleshooting「send-keys Enter が chat 入力を submit できないことがある」参照)

#### (2) 上り=イベント

委任直後、作業者の状態が `working` に遷移したことを確認してから、`herdr agent wait` で状態遷移を待ち受ける(詳細: Troubleshooting「wait の即時解決」参照)。`--until` を省略した場合のデフォルトで `idle` / `done` / `blocked` のいずれかにマッチして戻ってくるため、1コマンドで済む:

```bash
# gotcha: 対象が既に指定ステータスだと即座に解決してしまうため、working に遷移済みか確認してから仕掛ける
AGENT_NAME=<agent-name>
herdr agent get "$AGENT_NAME"

herdr agent wait "$AGENT_NAME" > "/tmp/wait-${AGENT_NAME}.json"
```

発火後、出力 JSON に含まれるステータスを確認して分岐する。`blocked` ならユーザーに承認を仰ぎ、`idle` / `done` なら `herdr agent read "$AGENT_NAME" --source recent --lines 50` で完了報告を確認する(`idle` の場合は完了と断定せず下記「相談 idle の判別」も併せて行う)。

**Constraints:**
- **MUST**: ログファイル名には `<agent-name>` を含める。複数 worktree を並行監視しているときに固定ファイル名だと内容が上書きされてしまうため
- **MUST**: `<agent-name>` は手順4でエージェントに付けたユニーク名。`herdr agent wait` / `herdr agent read` は pane-id ではなく agent 名を直接ターゲットにできるため、監視中に pane-id を引き直す必要がない
- **MUST NOT**: 定期ポーリング(`herdr pane list` 等を一定間隔で呼び続けるループ)は禁止。コストが高いうえ、このプロトコルが解消したいアンチパターンそのもの
- **MUST**: 特定のステータスだけを待ちたい場合は `--until <STATUS>` を明示する(繰り返し指定可、例: `--until blocked --until idle`)。`done` は herdr 0.7.5 以降 `--until` / デフォルトの両方で受理される(詳細: Troubleshooting「herdr agent wait の done 受理」参照)
- **MUST**: 似た用途で `herdr wait agent-status <pane-id> --status <...|done|...>` というコマンドもあるが、こちらは pane-id が必須の UI 向けのコマンド。CLI 主導のこのプロトコルでは agent 名を直接使える `herdr agent wait <agent-name>` を使う
- **MAY**: `--timeout`(ミリ秒)は省略可能で、省略すると無期限にブロックする。バックグラウンドで放置する分には問題ないが、安全弁として妥当な値を指定してもよい
- **MUST**: タイムアウトした場合は同じ wait を仕掛け直す(これは定期ポーリングではなく、イベント待ちの再武装)

**相談 idle の判別:**

作業者は【相談】送信後も司令塔からの回答を待つ間 `idle` に遷移する(手順4テンプレート「## 相談」参照)。そのため `idle` 発火は「完了」と「相談待ち」のどちらもありうる。

- **MUST**: `idle` 発火時は完了と断定せず、`herdr agent read "$AGENT_NAME" --source recent --lines 50` で直近ログを確認する。末尾付近に `【相談】` があれば「相談待ちの idle」、なければ「完了の idle」と判定する
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
`herdr agent start` の `--` 以降(`AGENT_ARG`)に複数行 heredoc の作業指示プロンプトをそのまま渡すと、`invalid_agent_argument: agent arguments cannot be encoded safely for the target shell` で拒否される(2026-07-30、#520 で実機確認)。回避策: 作業指示を司令塔自身のスクラッチパッドディレクトリにファイルとして書き、起動プロンプトは「<パス> を読み、その内容全体をあなたへの作業指示として忠実に実行してください。」の1行にする(手順4参照)。allowlist テンプレート(手順3「worktree の準備」参照)は「司令塔がタスク指示を置くスクラッチパッドの読み取り」を既に許可しており、この方式と整合している。

### ライブセッション検証時の誤 kill 事故
2026-07-05、作業者エージェントが検証用に起動したはずの Alacritty が実際にはマップされておらず、直後に `pgrep -af alacritty` で拾った PID をテスト用ウィンドウと誤認して kill し、ユーザーが元から開いていた既存の Alacritty(workspace 2)を誤終了させた(#354、PR #353)。自分が起動したプロセスは起動時の `$!` で PID を捕捉して追跡し、事後に名前ベースの `pgrep` で「自分のものらしきプロセス」を探して kill するのは禁止。

### send-text は単体では実行されない
`pane send-text` は pane の入力欄にテキストを挿入するだけで、送信(実行)はされない。実機確認済み: `send-text` の直後に `pane read` してもコマンドは未実行のまま入力欄に残っており、続けて `pane send-keys <pane-id> Enter` を送って初めて実行される。

### AskUserQuestion メニュー表示中の誤確定事故
2026-07-26、#494/#466 の並行 worktree 運用(worker 2体 + 司令塔)で、作業者への追加指示のつもりで送った `send-text` + Enter が、表示中だった AskUserQuestion メニューの選択肢1「GPG エージェントをリセットして再試行」を誤確定させた。作業者が `gpgconf --kill gpg-agent` を実行し、ユーザーが直前に温めたパスフレーズキャッシュが消える実害が出た(#498)。手順5(1)の Constraint の通り、送信前に必ず `herdr agent read` で pane の状態を確認し、メニュー表示中は send-text を使わない(選択肢の Enter 確定のみで応答するか、メニューの解除を待つ)。

### send-keys Enter が chat 入力を submit できないことがある
2026-07-26、#494/#466 の並行運用で、pane の入力欄にテキストが置かれたまま `pane send-keys <pane-id> Enter` が繰り返し効かず、作業者が再開できなくなった(同じ pane でメニューの選択肢確定には Enter が効いていたため、原因切り分けに時間を要した)。これは上記「send-text は単体では実行されない」(send-text だけでは実行されず別途 Enter が要る、という話)とは別の話 — real Enter を送っても Claude Code の chat 入力側で submit されないケースがある、という話。

当時の回避策(`herdr pane run <pane-id> ""` で空文字+real Enter を送り pending テキストを submit する)は herdr 0.7.5 では効かないケースが確認されている(2026-07-30、#520)。0.7.5 で新設された `herdr agent prompt <agent-name> <text>` はこの罠自体を踏まない上位互換の解で、入力欄に別テキストが残った状態でも正しく処理される。手順5(1)の標準手順は `agent prompt` に置換済み(詳細はそちらを参照)。`--wait` / `--until <STATUS>`(繰り返し指定可)/ `--timeout <MS>` を併用すれば送信と応答待ちを1コマンドに畳められる。

なお AskUserQuestion メニューの選択肢確定(ハイライト行の Enter)は、この submit 不全とは別の経路のため、従来どおり `pane send-keys <pane-id> Enter` で機能する。効かないのはあくまで chat 入力の submit。

### GPG 署名コミットは worker pane から pinentry を出せない
worker pane は tty を持たず(`GPG_TTY` も stale)、pinentry を表示できない構造がある。gpg-agent のパスフレーズキャッシュ(このリポジトリは TTL 8h)は agent プロセスのメモリ内にあり、`gpgconf --kill gpg-agent` や agent の再起動を行うと TTL に関係なく消える。運用(実機確認済み、2026-07-26、#494/#466、#498): ユーザーが自分の生きている端末で1回署名(例: `echo test | gpg --clearsign -o /dev/null`)してキャッシュを温めれば、同一セッションの全 worker のコミットが通るようになる。司令塔は `gpg-connect-agent 'keyinfo --list' /bye` の出力の cached フラグ(`1`)でキャッシュの有無を確認できる。署名コミットで詰まった場合、worker に `gpgconf --kill gpg-agent` 等でエージェントを殺させず、ユーザーに1回解除(署名)を依頼する。

この詰まりは委任前の事前チェックで予防できる。詳細は手順4「GPG パスフレーズキャッシュの事前チェック」参照。

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

### SendMessage は司令塔に届かない(構造的理由)
2026-07-04、copilot-quorum #303 の作業者が完了報告のため `SendMessage` を試行し、`You are the main conversation` エラーで失敗した(#341)。Claude Code のセッション間に直接チャネルはなく、作業者は自セッションの main のため司令塔という宛先が存在しない。上り報告は `SendMessage` ではなく、会話内テキスト出力(司令塔が `herdr agent read` で回収するプル型)と、herdr 経由の push(手順5「(3) 上り=内容」参照)の組み合わせで行う。

herdr が使えない環境(worktree だけで完結させたい等)では、作業者が report ファイルをスクラッチパッドに書き、司令塔が Monitor 等でポーリングするファイルベースのフォールバックも考えられる(#341 案C)。ただしポーリングコストがあり、herdr が使える環境では手順5「(3) 上り=内容」の下位互換にとどまるため、標準経路には採用していない。

### 相談待ち idle と完了 idle の判別
作業者は【相談】送信後も司令塔からの回答を待つ間 `idle` に遷移するため、`herdr agent wait` の `idle` 発火だけでは完了と断定できない(#394)。判別・応答の手順は手順5「(2) 上り=イベント」の「相談 idle の判別」参照。

### レビュー差し戻しラウンドによる worker context の逼迫
本業リポジトリの PR(2026-07-27)で、差し戻し2ラウンド後に worker が context 60% に到達し、ユーザーが先に検知した。差し戻しは元実装の全文脈を保持した worker に送るのが品質上望ましい一方、ラウンドごとに context は単調に増える。50% を目安に「直接対応 or 引き継ぎ」へ切り替える(上記手順5(1) の Constraint)。ステータスラインの使用率は `herdr agent get <agent-name>` で pane-id を引いてから `herdr pane read <pane-id> --source visible` を実行し、その末尾行で機械的に読める。

### commander-<repo名> の名前衝突
同リポジトリの過去セッション pane が名前を保持していると `herdr agent rename` が
`agent_name_taken` で失敗する。他 pane の rename は禁止(MUST NOT)のため、
`commander-<repo名>-2` のように数字サフィックス(またはタスク由来の意味サフィックス)を付けて自分を命名し、
**作業指示プロンプト内の宛先(【相談】【報告】の2箇所)も同じ名前に揃える**こと。
サフィックス付き名でも上り報告プロトコルはそのまま機能する(実機確認済み)。

3件の実例で再発しており、衝突は1回きりの偶発事象ではなく再発する運用パターンであることを示す:
- 2026-07-12 copilot-quorum: `commander-copilot-quorum` → `-2`
- 2026-07-18 dotfiles: `commander-dotfiles` → `-2` → `-3`(サフィックスが2つ埋まっている状態での発生)
- 2026-07-20 dotfiles: `commander-dotfiles` → 意味サフィックス `-dpp`。このケースでは保持者(pane `w3C:p2`)が過去セッションの残骸ではなく、**同リポジトリで別タスクを進行中の同時稼働 live セッション**だったことが判明した。この種の衝突は正当な同時運用が原因のため、stale 名の掃除では解決せず、サフィックス命名規定そのものが本質的な対応になる(意味サフィックスは複数司令塔が並行稼働時にどれがどれか識別しやすい利点がある)

### 非ASCII・不可視文字(PUA グリフ等)をファイルに書く場合
Nerd Font の PUA グリフ等をツール呼び出しで直接タイプすると、バイト列が消失して空文字列になったり、意図せず `\uXXXX` テキストに化けたりする(不可視文字はエディタ・diff・レビューUIのどこでも見えず、目視でのミス検出ができない構造的な罠 — #363、PR #366)。該当する書き込みは以下の手順で行う: JSON ファイルへは、コードポイントが BMP 内(U+FFFF 以下)なら `\uXXXX` エスケープをリテラル ASCII 文字列として書いてよいが、U+10000 以上(サロゲートペアが必要。Nerd Fonts 由来の記号で頻出、例: `U+F0A1E`)では `\uXXXX` 単体では表現できず手順が破綻するため、`python3 -c "import json; print(json.dumps('<文字>', ensure_ascii=True))"` 等でサロゲートペアのエスケープを機械生成して貼る。JSON 以外のファイルは Python の `chr()` でコードポイントから機械的に文字列を組み立ててファイル I/O で書き込む。書き込み後は hex dump(`xxd` 等)で機械的に検証する(目視確認は禁止)。コードポイントの正典は `ryanoasis/nerd-fonts` リポジトリの `glyphnames.json`。
