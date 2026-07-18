---
name: wtclean
description: "マージ済み PR に対応する worktree / workspace / ローカルブランチを安全に掃除する。/wt で作った worktree のライフサイクルの後始末。ユーザーが「worktree を掃除して」「片付けたい」「/wtclean」と言った時に使う。"
---

# Worktree 掃除 (herdr)

## Overview

マージ済み PR に対応する worktree / workspace / ローカルブランチを安全に掃除します。
`/wt` で作った worktree のライフサイクルの後始末を担う、対になるコマンドです。

## Parameters

- **`--force`**(任意): 指定すると dry-run をスキップし、確認後すぐに削除を実行する。省略時(デフォルト)は dry-run(削除対象の一覧提示まで)で終了し、実際の削除はユーザーの確認を取ってから行う(実体は末尾の [引数](#引数) セクション参照)

## Steps

### 1. リポジトリの確認

**Constraints:**
- **MUST**: `git rev-parse --show-toplevel` でリポジトリルートを確認する
- **MUST**: git リポジトリでない場合は中断してユーザーに知らせる

### 2. マージ済み PR の head ブランチ一覧を取得

```bash
gh pr list --state merged --limit 50 --json number,headRefName,title
```

**Constraints:**
- **MUST**: 上記コマンドでマージ済み PR の head ブランチ一覧を取得する

### 3. worktree との突き合わせ

`herdr worktree list` と `git worktree list` の結果を突き合わせて、マージ済みブランチに対応する worktree を特定する。

**Constraints:**
- **MUST**: `herdr worktree list` と `git worktree list` の結果を突き合わせて、マージ済みブランチに対応する worktree を特定する
- **MUST**: マージ済みブランチに対応する worktree が1つもなければ「掃除対象なし」と報告して終了する

### 4. 各対象の安全チェック

各 worktree について以下をすべて確認する。1つでも引っかかったらその worktree はスキップし、理由付きで報告リストに回す(削除はしない)。

**Constraints:**
- **MUST**: 未コミット変更がないこと(worktree 内で `git status --short` が空であること)を確認する
- **MUST**: エージェントが稼働中でないこと(`herdr agent list` で、その workspace のエージェントが `working` / `blocked` 状態でないこと)を確認する
- **MUST**: open PR が紐づいていないこと(`gh pr list --state open --head <branch>` が空であること)を確認する
- **MUST**: 1つでも引っかかったらその worktree はスキップし、理由付きで報告リストに回す(削除はしない)

### 5. 削除対象の提示と確認

削除対象・スキップ対象(理由付き)の一覧をユーザーに提示する。

**Constraints:**
- **MUST**: 削除対象・スキップ対象(理由付き)の一覧をユーザーに提示する
- **MUST**: dry-run(デフォルト)ではここで終了し、「実行するには確認してね」と伝える
- **MUST**: ユーザーが削除を承認した場合のみ、次の手順に進む

### 6. 知見の回収(供養)

削除が承認されたら、実際に `herdr worktree remove` を実行する**前**に、各対象 worktree の pane ログから摩擦・回避策を抽出する。対話プロトコル(`/wt` 手順5、#332)の4本柱のうち「供養」にあたる工程で、worktree を消す前に知見を回収する。

対象 worktree の pane を特定する(`herdr worktree list` で得た `open_workspace_id` を使う):

```bash
herdr pane list --workspace <workspace-id>
```

`"agent": "claude"` が付いている pane が作業者エージェントの pane。そのログを読む:

```bash
herdr pane read <agent-pane-id> --source recent-unwrapped --lines 500
```

**Constraints:**
- **MUST**: 削除が承認されたら、`herdr worktree remove` 実行前に各対象 worktree の pane ログから摩擦・回避策を抽出する
- **MUST**: 抽出対象は作業指示テンプレートの「## 報告」内の「気づき」欄(指示外の回避策・環境の摩擦・想定外の挙動)、および permission ブロックやリトライなど、ログ上に残る摩擦の痕跡とする
- **MUST**: workspace がすでに閉じていて pane が読めない場合はスキップし、その旨を報告に含める
- **MUST**: 抽出した内容を worktree ごとに要約し、Issue 化する価値がありそうなものは候補としてユーザーに提示する
- **MAY**: worker の開発過程に記録価値がある場合(非自明な設計判断・戦略が奏功した・規範文書を根拠にした境界判断など)、session-log スキルの流儀で子ノートを作成してよい。命名は `ResearchNotes/ClaudeCodeSession-YYYYMMDD-Worker-<TopicSlug>.md`(`ClaudeCodeSession-` プレフィックスを維持し .base ビューのフィルタを壊さない)、frontmatter に `parent: "[[<司令塔セッションノート名>]]"` を付け、本文冒頭に親への wikilink を置く
- **MUST NOT**: 全 worker に子ノートを作らない。記録価値で厳選する(摩擦の抽出だけで足りるものはメモリ/Issue 候補のみ)
- **MUST**: 提示した候補のうち Issue 化を進めるものは自己更新プロトコル(`/wt` 手順7「自己更新(Self-update)」参照)に渡す。司令塔はそこでフィルター(再発しうる・タスク横断的)を適用し、対象の知見を diff 案付きの Issue として起案する
- **MUST NOT**: この時点では `gh issue create` は実行しない(ユーザーが必要と判断したものだけ、別途 Issue 化する)
- **MUST**: 気づきがない、または些末な場合は「知見なし」として次に進む

### 7. 削除の実行

承認された各対象について:

```bash
herdr worktree remove --workspace <workspace-id>
git branch -d <branch>
```

最後にまとめて:

```bash
git worktree prune
```

**Constraints:**
- **MUST**: 承認された各対象について `herdr worktree remove --workspace <workspace-id>` と `git branch -d <branch>` を実行する
- **MUST**: 最後にまとめて `git worktree prune` を実行する
- **MUST**: `git branch -d` を使う(merged 確認済みのため)
- **MUST NOT**: `-D` は使わない
- **MUST**: `git branch -d` が「not yet merged to HEAD」警告を出した場合はローカル main を更新してから再実行する(それでも `-D` にはエスカレートしない。詳細: Troubleshooting「git branch -d の not yet merged to HEAD 警告」参照)

### 8. 結果の報告

以下を一覧で報告する:

**Constraints:**
- **MUST**: 削除したもの(ブランチ名 / worktree パス / workspace ID)を報告する
- **MUST**: スキップしたもの(理由付き: 未コミット変更あり、エージェント稼働中、open PR あり、など)を報告する
- **MUST**: 回収した知見 / Issue 候補を報告する(worktree ごとに要約。該当なしなら「知見なし」)

## Examples

```
/wtclean
/wtclean --force   # dry-run をスキップして確認後すぐ削除
```

## Troubleshooting

### git branch -d の not yet merged to HEAD 警告
squash マージ運用ではマージされたブランチのコミットが main の履歴に直接は含まれないため、ローカル main が最新であってもこの警告は出る(ローカル main の遅延が原因とは限らない)。手順2で origin(の同名ブランチ)へのマージは確認できているので、`git branch -d` が upstream 追跡ブランチへのマージ済みと判定すれば、警告付きで削除は成功する。この場合は警告を無視してよい。`-d` が実際に拒否された(削除されなかった)場合のみ、ローカル main を更新してから再実行する(それでも `-D` にはエスカレートしない)。更新方法: main をチェックアウト中のリポジトリでは `git fetch origin main:main` は拒否されるため、`git fetch origin` してから `git merge --ff-only origin/main`(または `git pull --ff-only`)で更新する。それでも拒否される場合は削除を中止してユーザーに報告する。
