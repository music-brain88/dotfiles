# Worktree 掃除 (herdr)

マージ済み PR に対応する worktree / workspace / ローカルブランチを安全に掃除します。
`/wt` で作った worktree のライフサイクルの後始末を担う、対になるコマンドです。

## 使い方

```
/wtclean
/wtclean --force   # dry-run をスキップして確認後すぐ削除
```

デフォルトは dry-run(削除対象の一覧提示まで)。実際の削除はユーザーの確認を取ってから行う。

## 手順

### 1. リポジトリの確認

`git rev-parse --show-toplevel` でリポジトリルートを確認する。
git リポジトリでない場合は中断してユーザーに知らせる。

### 2. マージ済み PR の head ブランチ一覧を取得

```bash
gh pr list --state merged --limit 50 --json number,headRefName,title
```

### 3. worktree との突き合わせ

`herdr worktree list` と `git worktree list` の結果を突き合わせて、
マージ済みブランチに対応する worktree を特定する。

- マージ済みブランチに対応する worktree が 1 つもなければ「掃除対象なし」と報告して終了

### 4. 各対象の安全チェック

各 worktree について以下をすべて確認する。**1 つでも引っかかったらその worktree はスキップ**し、理由付きで報告リストに回す(削除はしない):

1. **未コミット変更がないこと**: worktree 内で `git status --short` が空であること
2. **エージェントが稼働中でないこと**: `herdr agent list` で、その workspace のエージェントが `working` / `blocked` 状態でないこと
3. **open PR が紐づいていないこと**: `gh pr list --state open --head <branch>` が空であること

### 5. 削除対象の提示と確認

削除対象・スキップ対象(理由付き)の一覧をユーザーに提示する。

- dry-run(デフォルト)ではここで終了し、「実行するには確認してね」と伝える
- ユーザーが削除を承認した場合のみ、次の手順に進む

### 6. 削除の実行

承認された各対象について:

```bash
herdr worktree remove --workspace <workspace-id>
git branch -d <branch>
```

最後にまとめて:

```bash
git worktree prune
```

- `git branch -d` は merged 確認済みなので `-d` を使う。**`-D` は使わない**
- ローカル main が origin より遅れていると `git branch -d` が「not yet merged to HEAD」警告を出すことがあるが、手順 2 で origin へのマージが確認できているので、その場合は `git fetch origin main:main` などでローカル main を更新してから再実行する(それでも `-D` にはエスカレートしない)

### 7. 結果の報告

以下を一覧で報告する:

- 削除したもの(ブランチ名 / worktree パス / workspace ID)
- スキップしたもの(理由付き: 未コミット変更あり、エージェント稼働中、open PR あり、など)

## 引数

$ARGUMENTS
