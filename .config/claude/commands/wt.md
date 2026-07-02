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
herdr agent start claude --workspace <workspace-id> --focus -- claude "<タスクの説明>"
```

タスクが曖昧な場合は起動せず、workspace の準備完了だけ報告して終わる。

## 引数

$ARGUMENTS
