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

`herdr worktree list --cwd <repo-root>` と `git worktree list` の結果を突き合わせて、マージ済みブランチに対応する worktree を特定する。

**Constraints:**
- **MUST**: `herdr worktree list --cwd <repo-root>` と `git worktree list` の結果を突き合わせて、マージ済みブランチに対応する worktree を特定する(`--cwd` を省略するとフォーカス中 workspace のリポジトリが返り、複数リポジトリ並行時に別リポジトリの一覧と突き合わせてしまう — 2026-07-12 copilot-quorum セッションで実機確認)
- **MUST**: マージ済みブランチに対応する worktree が1つもなければ「掃除対象なし」と報告して終了する

### 4. 各対象の安全チェック

各 worktree について以下をすべて確認する。1つでも引っかかったらその worktree はスキップし、理由付きで報告リストに回す(削除はしない)。

**Constraints:**
- **MUST**: 未コミット変更がないこと(worktree 内で `git status --short` が空であること)を確認する
- **MUST**: エージェントが稼働中でないこと(`herdr agent list` で、その workspace のエージェントが `working` / `blocked` 状態でないこと)を確認する
- **MUST**: open PR が紐づいていないこと(`gh pr list --state open --head <branch>` が空であること)を確認する
- **SHOULD**: 同一リポジトリに他の司令塔 pane(`commander-<repo名>*` の別名義)が存在するか `herdr agent list` で確認し、存在する場合は「並行 /wtclean のレースがありうる」旨を dry-run の提示に含める
- **MUST**: 1つでも引っかかったらその worktree はスキップし、理由付きで報告リストに回す(削除はしない)

### 5. 削除対象の提示と確認

削除対象・スキップ対象(理由付き)の一覧をユーザーに提示する。

**Constraints:**
- **MUST**: 削除対象・スキップ対象(理由付き)の一覧をユーザーに提示する
- **MUST**: dry-run(デフォルト)ではここで終了し、「実行するには確認してね」と伝える
- **MUST**: ユーザーが削除を承認した場合のみ、次の手順に進む

### 6. 知見の回収(供養)

削除が承認されたら、実際に `herdr worktree remove` を実行する**前**に、各対象 worktree の pane ログから摩擦・回避策を抽出する。対話プロトコル(`/wt` 手順5、#332)の4本柱のうち「供養」にあたる工程で、worktree を消す前に知見を回収する。

対象 worktree の pane を特定する(`herdr worktree list --cwd <repo-root>` で得た `open_workspace_id` を使う):

```bash
herdr pane list --workspace <workspace-id>
```

`"agent": "claude"` が付いている pane が作業者エージェントの pane。**複数ある場合(worker 引き継ぎ運用をした worktree)はすべて読む**。各 pane のログを読む:

```bash
herdr pane read <agent-pane-id> --source recent-unwrapped --lines 500
```

**Constraints:**
- **MUST**: 削除が承認されたら、`herdr worktree remove` 実行前に各対象 worktree の pane ログから摩擦・回避策を抽出する
- **MUST**: `"agent": "claude"` の pane が複数ある場合(context 逼迫による worker 引き継ぎ運用の痕跡)は全 pane を読む。引き継ぎチェーンでは前任(引き継ぎ元)pane に罠の発見・原因究明・引き継ぎ判断など価値の高い知見が残りやすいため、前任側を省略しない
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
- **MUST**: 各対象の削除直前に worktree パスとブランチの存在を個別に再検証する。他セッションが `herdr worktree remove` を済ませ `git branch -d` を未実行の窓ではパスのみ消失してブランチが残ることがあるため、パスが消えていてもブランチが存在する限り `git branch -d` は試みる。両方消えている場合のみ「他セッションが掃除済み」としてスキップし、結果報告にその旨を含める(エラーとして扱わない)
- **MUST**: `herdr worktree remove --workspace <workspace-id>`(内部で実行される `git worktree remove` 由来のエラーを含む)/ `git branch -d` の「対象なし」系エラー(`not a working tree` / `branch not found`)は、並行掃除の痕跡として握りつぶさず報告に記録する
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

### 9. 収穫ステップ(蒸留パイプライン Hot lane)

手順8の掃除完了報告の**後**に行う。蒸留パイプライン設計(vault ProjectNotes)の合意事項: 蒸留の実行トリガーは
時刻ではなく**作業サイクルの完了**に置く。「マージ済み作業の後始末」である /wtclean は、その天然の完了の拍にあたる。

削除した各 worktree について、対応する PR 番号(手順2で取得済み)を使い、リポジトリの中で同梱スクリプトを呼んで、
ResearchNotes 配下の ClaudeCodeSession ノートを検索する:

```bash
bash ~/.claude/skills/wtclean/harvest_search.sh <PR番号>
```

スクリプトは、このリポジトリの PR を引用したノートのパスを 1 行 1 件で stdout に出す。終了コードは grep と同じ並びで、
0 はヒットあり、1 はヒットなし、2 は検索できなかったこと(理由は stderr)を表す。ノートの置き場は既定で
`/home/archie/Documents/Obsidian/Zettelkasten/ResearchNotes/` で、第 2 引数で別の置き場を渡せる。ノートは読むだけで変更しない。

PR の番号だけではリポジトリが決まらない。そこでスクリプトは、自分の `owner/repo` を `gh repo view` で求め
(`gh` で求められないときは origin の URL から求め、両方だめなら終了コード 2 で止まる)、次の規則でノートを選ぶ:

- 次のどれかを含むノートはヒットする: (1) 自分の `owner/repo#<PR番号>`、(2) `https://github.com/<自分の owner/repo>/pull/<PR番号>`、
  (3) リポジトリの修飾が付かない `#<PR番号>`(`#663` や `PR#663` の形)。`owner/repo` の大文字小文字は区別しない
- 別のリポジトリの `<owner>/<repo>#<PR番号>` と `github.com/<owner>/<repo>/pull/<PR番号>` だけで番号を引用したノートはヒットしない
- どの形も、PR 番号の直後に数字が続かない境界を確かめる。例: PR 53 を探すとき、`#534` や `pull/534` を誤ってヒットさせない

(3) の修飾なしの `#<PR番号>` は、どのリポジトリの PR かを検索では決められないが、わざとヒットさせる。セッションノートは
「決定事項・成果物」節に `[PR #534](https://github.com/.../pull/534)` の形で PR リンクを残す運用で、このリポジトリの PR を
修飾なしの `#N` で書くことが多い。修飾なしの形を除くと、誤検知が減るよりも取りこぼしが増える。修飾なしの `#N` で別の
リポジトリの PR を書いたノートは、従来どおり誤ってヒットしうる。

ヒットしたノートの frontmatter `distilled_to:` が空のものを候補とする。

**Constraints:**
- **MUST**: 削除した各 worktree の PR 番号で同梱スクリプト `harvest_search.sh` を呼び、ヒットしたノートのうち
  `distilled_to` が空のノートを候補とする。検索を SKILL.md の外の手書きの grep で代用しない(番号だけの grep は、
  別のリポジトリの同じ番号の PR を引用したノートにもヒットする。Troubleshooting「収穫ステップが別リポジトリの同じ番号の PR を拾う」参照)
- **MUST**: スクリプトが終了コード 2 で止まった場合は、stderr の理由を一言添えて収穫ステップを終える(掃除の結果には影響させない)
- **MUST**: 候補が複数あっても提案は1件のみに絞る(複数 worktree を掃除した場合など。最初に見つかったものでよい)
- **MUST**: 候補が見つかったら `/distill <ノートパス>` による軽量蒸留を**提案**する
- **MUST**: 提案は soft gate として行う。ユーザーが skip したら、それ以上食い下がらずそのまま終了する
  (skip してもそのノートは蒸留キューに残るだけで害はない——罪悪感でループを殺さない、という設計意図をここに残す)
- **MUST**: 対応する候補が1件も見つからない場合は何も言わずに終了する(ノイズを増やさない)
- **MUST NOT**: この手順は手順1〜8(dry-run・安全チェック・削除・報告)の判定や結果に一切影響してはならない
  (収穫ステップの成否に関わらず、掃除自体は手順8の時点で完了している)

## Examples

```
/wtclean
/wtclean --force   # dry-run をスキップして確認後すぐ削除
```

## Troubleshooting

### git branch -d の not yet merged to HEAD 警告
squash マージ運用ではマージされたブランチのコミットが main の履歴に直接は含まれないため、ローカル main が最新であってもこの警告は出る(ローカル main の遅延が原因とは限らない)。手順2で origin(の同名ブランチ)へのマージは確認できているので、`git branch -d` が upstream 追跡ブランチへのマージ済みと判定すれば、警告付きで削除は成功する。この場合は警告を無視してよい。`-d` が実際に拒否された(削除されなかった)場合のみ、ローカル main を更新してから再実行する(それでも `-D` にはエスカレートしない)。更新方法: main をチェックアウト中のリポジトリでは `git fetch origin main:main` は拒否されるため、`git fetch origin` してから `git merge --ff-only origin/main`(または `git pull --ff-only`)で更新する。それでも拒否される場合は削除を中止してユーザーに報告する。

### 並行 /wtclean のレース(複数司令塔)
同一リポジトリで複数の司令塔セッションが /wtclean を並行実行すると、dry-run で提示した
対象が実行時には他セッションにより削除済みになりうる(2026-07-18 実例: dry-run 時点で
worktree ディレクトリのみ消失した幽霊エントリを観測、実行時に branch not found)。
worktree パスとブランチの消失は独立に起こりうる(他セッションの `herdr worktree remove`
実行後・`git branch -d` 未実行の窓ではパスのみ消えてブランチは残る)ため、削除直前の
再検証(手順7)ではパスとブランチを個別に確認し、両方消えている場合のみ「掃除済み
スキップ」として扱う。片方だけ残っていれば残っている方の削除は試みる。供養(手順6)
も同様に、pane ログが他セッションの掃除で消失している場合はスキップして報告する。

### 収穫ステップが別リポジトリの同じ番号の PR を拾う
2026-10-04 に PR #663 の worktree を掃除したとき、手順 9 の検索が 2 か月前のセッションノートを 1 本拾った。そのノートは、
別のリポジトリの `<owner>/<repo>#663` と、その `pull/663` の URL を引用していた。このリポジトリの PR #663 とは無関係で、
司令塔は目で誤検知と判断して蒸留を提案しなかった(Issue #667)。

当時の検索は、`#<PR番号>` か `pull/<PR番号>` を含むノートを 1 行の grep で探し、番号の直後に数字が続かないことだけを
確かめていた。PR の番号はリポジトリごとに 1 から振られるので、番号だけではどのリポジトリの PR かが決まらない。
`/wtclose` の締めの検問が状態ファイルの書式に `owner/repo#N` の修飾子を入れた(PR #663)のも、同じ問題への対処である。

今は同梱スクリプト `harvest_search.sh` が、自分の `owner/repo` を求めたうえで、別のリポジトリの修飾付きの `#N` と
`pull/N` の URL だけを引用したノートを除く(規則は手順 9 参照)。検索をスクリプトに置いたのは、この判定が 1 行の grep に
収まらないことと、SKILL.md の本文にドル記号と数字の形を書くと、skill を引数つきで呼んだときに Claude Code が位置引数として
置き換えて壊すこと(#666)の 2 つが理由である。スクリプトのファイルは置き換えの対象にならない。

スクリプトの規則は同梱テスト `tests/harvest_search_test.sh`(`mise run claude:wtclean-test`)が確かめる。テストは一時
ディレクトリに作ったノートと偽の `gh` だけを使い、実物の vault を読まない。
