# Worktree 作成 (herdr)

タスクの説明からブランチ名を自動生成し、herdr の worktree + workspace を立ち上げます。

## 使い方

```
/wt CIのキャッシュが壊れてるのを直したい
/wt nvimにcopilot連携を追加する
```

## 手順

### 1. リポジトリの確認

`git rev-parse --show-toplevel` でリポジトリルートを確認する。
git リポジトリでない場合は中断してユーザーに知らせる。

### 2. ブランチ名の生成

ユーザーの入力（`$ARGUMENTS`）からブランチ名を生成する。

命名規則:

- conventional commit message のような形式で生成する（`feat/` `fix/` `chore/` `ci/` `docs/` などの type を prefix にする）
- prefix 以降は英語の snake_case で、単語 2〜4 個を目安に簡潔に
- 迷ったら `feat/` か `fix/` に寄せる

生成したブランチ名が既存ブランチと重複していないか `git branch --list <name>` で確認し、
重複する場合は接尾辞を変えて再生成する。

### 3. worktree + workspace の作成

```bash
herdr worktree create --cwd <repo-root> --branch <branch-name> --base main --focus
```

- ベースブランチはデフォルト `main`。ユーザーが入力内で別のベースを指定した場合はそれに従う
- 作成結果（worktree のパス、workspace ID）をユーザーに報告する

#### worktree の準備

worktree 作成直後に以下を行う:

- `mise trust <worktree-path>` を実行する（mise trust は絶対パス単位で管理されるため、新規 worktree は毎回 untrusted で始まる。忘れると `mise run` が「no tasks defined」で失敗する — #335）
- allowlist を配置する: `mkdir -p <worktree-path>/.claude && cp ~/.claude/templates/wt-settings.local.json <worktree-path>/.claude/settings.local.json`
  - コピー元は `<repo-root>/.config/claude/templates/...` ではなく `~/.claude/templates/...` を使う。`<repo-root>` は `/wt` を呼び出した対象リポジトリ次第で変わり、dotfiles 以外のリポジトリではこのテンプレートを含まないため
  - `~/.claude` への反映は home-manager 経由(`home.nix` の `home.file ".claude".source = ./.config/claude`)で、`mise run nix:switch` 実行時に `/nix/store` スナップショットへの per-file symlink が生成される方式。テンプレートを追加・変更したら `mise run nix:switch` を実行しないと `~/.claude/templates/` に反映されない。`cp` が `No such file or directory` で失敗したら、まず nix:switch 漏れを疑う
  - 定型で安全な操作（`git`・`gh`・`mise`・`herdr` の一部サブコマンド、司令塔がタスク指示を置くスクラッチパッドの読み取り）を宣言的に許可し、作業者の permission 往復（A類）を設計で消す。詳細は allowlist テンプレート本体を参照

### 4. エージェントの起動（任意）

タスク内容が具体的な場合、新しい workspace でエージェントを起動してタスクを渡す:

```bash
herdr agent start claude-<branch-name 由来のユニーク名> --workspace <workspace-id> --cwd <worktree-path> --split down --focus -- claude --model claude-sonnet-5 --effort <effort> --permission-mode auto "$(cat <<'PROMPT'
<作業指示プロンプト（複数行可）>
PROMPT
)"
```

- `--cwd` は必須。省略すると呼び出し元シェルの cwd（リポジトリ本体）を引き継ぎ、worktree 外で作業が始まってしまう
- `--split down` で pane を上下分割にする（省略時はデフォルトの `right` で左右分割になってしまう）
- エージェント名はセッション全体でユニーク制約があるため、固定名 `claude` ではなくブランチ名由来の名前にする
- 変換ルール: ブランチ名から prefix（`fix/` 等）を除き、`_` と `/` を `-` に置換して `claude-` を前置する（例: `fix/wt_agent_start_options` → `claude-wt-agent-start-options`）
- 作業者モデルはデフォルト `claude-sonnet-5`（司令塔=メインセッションが計画とレビュー、作業者が実装を担う分業）。ユーザーが入力内で別モデルを指定した場合はそれに従う
- `--permission-mode auto` で起動する。定型操作は自動承認され、判断が必要な操作だけが blocked として表面化する（`--dangerously-skip-permissions` は使わない — 監督を全て外すのではなく、エスカレーションのレーンを残すのが目的）
- それでも blocked が発生した場合、司令塔は代理承認できない（Claude Code が禁止している）。司令塔の責務は「即検知して人間に知らせる」まで（#332 の対話プロトコル参照）
- auto mode での起動自体がハーネス（auto mode 分類器）に「ユーザーの明示許可がない」として拒否されることがある。その場合は AskUserQuestion 等でユーザーに auto mode 起動の許可を明示的に確認してから再実行する

タスクが曖昧な場合は起動せず、workspace の準備完了だけ報告して終わる。

#### effort の選択基準

司令塔がタスクの難易度を見て判断する:

| effort | 使いどころ |
|--------|-----------|
| medium | 定型・機械的な変更（バージョン bump、typo 修正、設定1行の変更） |
| high | 通常の実装タスク（迷ったらこれ。Sonnet 5 のデフォルト） |
| xhigh | 難しい実装・複数ファイルにまたがる変更・設計判断を含むタスク |

- `low` は under-thinking のリスクがあるため /wt では使わない
- `medium` 以下では Sonnet 5 が指示を literal に解釈するため、作業指示プロンプトの完了条件を具体的に書くことが特に重要

#### 作業指示プロンプトのテンプレート

```
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
- 判断に迷う大きな設計変更はせず、迷った点は最終報告に書く

## 報告
完了したら、変更ファイル・PR の URL・確認した動作を簡潔にまとめて報告する。指示外の気づき（環境の摩擦・想定外の挙動・自分で編み出した回避策）があれば、解決済みであっても必ず報告する（該当なしなら「なし」と明記する）
```

背景と完了条件を具体的に書くほど作業品質が安定する。

### 5. 対話プロトコル（委任後の監視と対話）

エージェント起動後、司令塔（このセッション）と作業者エージェントの間のやり取りは、以下の4本柱からなる対話プロトコルとして運用する（設計の背景は #332 参照）。ここでは (1) 下り=指示 と (2) 上り=イベント を扱う。(3) 上り=内容 は上記の作業指示プロンプトの「## 報告」欄、(4) 供養 は `/wtclean` 側で扱う。

#### (1) 下り=指示

委任時の指示は手順4の heredoc テンプレートで渡す。委任後に追加の指示を送りたい場合は、pane へのテキスト送信と Enter 送信を分けた2段で行う:

```bash
herdr pane send-text <pane-id> "<追加指示のテキスト>"
herdr pane send-keys <pane-id> Enter
```

- `pane send-text` は pane の入力欄にテキストを挿入するだけで、送信（実行）はされない。実機確認済み: `send-text` の直後に `pane read` してもコマンドは未実行のまま入力欄に残っており、続けて `pane send-keys <pane-id> Enter` を送って初めて実行される
- `<pane-id>` は対象エージェント名から `herdr agent list` で引く（`pane_id` フィールド）
- 宛先を誤ると、無関係な pane やこの司令塔自身の入力欄にテキストが挿入されてしまう（`agent send` / `pane send-text` はテキストを引数としてそのまま送るだけで、確認や取り消しは挟まらない）。実行前に対象の pane-id / agent 名を必ず確認する
- pane-id はセッション中に compact されうる非永続 ID（詳細は `.config/claude/skills/herdr/SKILL.md` 参照）。長時間の監視をまたぐ場合は都度 `herdr agent list` で引き直し、古い pane-id を使い回さない

#### (2) 上り=イベント

委任直後、作業者の状態が `working` に遷移したことを確認してから、`blocked`（詰まり）と `idle`（完了）の2状態を同時にバックグラウンドで待ち受ける:

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

- ログファイル名には `<agent-name>` を含める。複数 worktree を並行監視しているときに固定ファイル名だと内容が上書きされてしまうため
- `wait -n` は bash 組み込みで、バックグラウンドの2ジョブのうち先に終了した方を検知する。ただし `wait -n` 自身はどちらが終了したかを返さないため、直後に `kill -0 "$BLOCKED_PID"`(シグナルを送らず存否だけ確認する)で生死を見て、生きている方=発火しなかった方、と判別してから後処理する。判別できたら `$FIRED_STATUS` を見て、`blocked` ならユーザーに承認を仰ぎ、`idle` なら `herdr agent read "$AGENT_NAME" --source recent --lines 50` で完了報告を確認する。まだ生きている側の wait は用済みなので kill で片付ける
- `<agent-name>` は手順4でエージェントに付けたユニーク名。`herdr agent wait` / `herdr agent read` は pane-id ではなく agent 名を直接ターゲットにできるため、監視中に pane-id を引き直す必要がない
- 定期ポーリング（`herdr pane list` 等を一定間隔で呼び続けるループ）は禁止。コストが高いうえ、このプロトコルが解消したいアンチパターンそのもの
- gotcha（実機確認済み）: `herdr agent wait` は対象が**既に**指定ステータスだと即座に解決する。作業者がまだ `working` に遷移していない段階で `idle` 待ちを仕掛けると、起動直後の未初期化状態を完了と誤検知しかねない
- `--status done` は使わない。`herdr agent wait` に `done` を渡すとエラーになる（実機確認済みのエラーメッセージ: `done is a UI attention state; use idle for CLI agent completion waits`）。`done` は「人間がまだ見ていない完了」を表す UI 向けの状態で、CLI から作業完了を検知するときは `idle` を使う
- 似た用途で `herdr wait agent-status <pane-id> --status <...|done|...>` というコマンドもあるが、こちらは pane-id が必須かつ `done` を受け付ける UI 向けのコマンド。CLI 主導のこのプロトコルでは agent 名を直接使える `herdr agent wait <agent-name>` を使う
- `--timeout`（ミリ秒）は省略可能で、省略すると無期限にブロックする（実機確認済み）。バックグラウンドで放置する分には問題ないが、安全弁として妥当な値を指定してもよい。タイムアウトした場合は同じ2つの wait を仕掛け直す（これは定期ポーリングではなく、イベント待ちの再武装）

## 引数

$ARGUMENTS
