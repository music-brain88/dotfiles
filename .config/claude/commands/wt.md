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

### 4. エージェントの起動（任意）

タスク内容が具体的な場合、新しい workspace でエージェントを起動してタスクを渡す:

```bash
herdr agent start claude-<branch-name 由来のユニーク名> --workspace <workspace-id> --cwd <worktree-path> --split down --focus -- claude --model claude-sonnet-5 --effort <effort> "<作業指示プロンプト>"
```

- `--cwd` は必須。省略すると呼び出し元シェルの cwd（リポジトリ本体）を引き継ぎ、worktree 外で作業が始まってしまう
- `--split down` で pane を上下分割にする（省略時はデフォルトの `right` で左右分割になってしまう）
- エージェント名はセッション全体でユニーク制約があるため、固定名 `claude` ではなくブランチ名由来の名前にする
- 変換ルール: ブランチ名から prefix（`fix/` 等）を除き、`_` と `/` を `-` に置換して `claude-` を前置する（例: `fix/wt_agent_start_options` → `claude-wt-agent-start-options`）
- 作業者モデルはデフォルト `claude-sonnet-5`（司令塔=メインセッションが計画とレビュー、作業者が実装を担う分業）。ユーザーが入力内で別モデルを指定した場合はそれに従う

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
完了したら、変更ファイル・PR の URL・確認した動作を簡潔にまとめて報告する
```

背景と完了条件を具体的に書くほど作業品質が安定する。

## 引数

$ARGUMENTS
