---
name: session-log
description: |
  エージェントセッションの意思決定・洞察・成果物を Obsidian の ResearchNotes に昇格させる(蒸留パイプライン層1)。
  ユーザーが「セッションをまとめて」「記録して」「/session-log」と言ったときに使う。
  また、設計判断・アーキテクチャ決定・重要な学びが生まれたセッションの区切り(タスク完了時・終了間際)には、こちらから記録を提案してよい。
  生ログの全転写ではなく、対話で生まれた判断・設計・学びの厳選記録。
---

# セッションログを ResearchNotes へ昇格

エージェントセッションでの意思決定・洞察・成果物を Obsidian の ResearchNotes に昇格させる。
生ログの全転写ではなく、対話で生まれた判断・設計・学びを厳選して記録する層(層1)を担う。
層2(Permanent Notes への蒸留)はユーザー自身が週次レビューで行うため、このスキルは踏み込まない。
ResearchNotes は Zenn 下書きの供給源でもある。週次レビューで「外に出せる知見」を1本選ぶ。

## 起動方法

- **明示起動**: `/session-log` または `/session-log <トピック>` — 即実行する
  - 引数なし: セッションの内容からトピックを自動推定する
  - トピックあり: それを元にファイル名・タイトルを決める
- **自発起動**: 以下をすべて満たすとき、セッションの区切りで記録を**提案**する(書き込みはユーザーの了承後)
  - 設計判断・アーキテクチャ決定・非自明な学びが1つ以上生まれた
  - 単純な作業代行(タイポ修正・定型操作のみ)のセッションではない
  - このセッションでまだ session-log を作成していない

## 実行環境トリアージ

本スキルは手順の宣言であり、特定の実行環境に依存しない。書き込み手段は以下の優先順で選ぶ:

| 環境 | 書き込み手段 |
|---|---|
| ローカル CLI エージェント(Claude Code・Copilot CLI 等) | ファイル直接読み書き |
| Claude Desktop / claude.ai(クラウディア) | Filesystem MCP(許可ディレクトリに vault が必要) |
| 書き込み手段なし(モバイル・MCP未接続) | ノート全文を chat に markdown で出力し、ユーザーが後で取り込む |

いずれの場合も手順・フォーマット・記録の原則は同一。

## 前提情報

- Vault: `/home/archie/Documents/Obsidian/Zettelkasten/`(ファイル直接読み書き。Obsidian MCP は使わない。WSL ではこのパスは Windows 側 vault への symlink — nix/modules/wsl.nix が管理)
- **出自の判定**: vault は全マシン共有(Obsidian Sync)なので、どこで書いたかを frontmatter に刻む。`uname -r` に `microsoft` を含む → 仕事機なので `context: work` / `machine: wsl`。それ以外(native Arch)→ `context: personal` / `machine: arch-native`
- **パス・運用ルールの単一の真実**: `Zettelkasten/MOC-ObsidianWorkflow.md` の「アクセスパターン宣言」。本スキルの記載と食い違う場合はそちらを優先し、差分を報告する
- 保存先: `ResearchNotes/ClaudeCodeSession-YYYYMMDD-<TopicSlug>.md`(TopicSlug は PascalCase の英語)
- デイリーノート: `DailyNotes/YYYY-MM-DD.md`(フラット構造・年月フォルダなし)
- 一覧ビュー: `Zettelkasten/ClaudeCodeSessions.base`(未蒸留の山。ファイル名プレフィックス `ClaudeCodeSession-` がビューのフィルタ条件なので命名規則を崩さない)
- vault は git 管理下。session-log の書き込み自体は通常編集でよい(コミットはユーザーの日次運用に委ねる)が、書き込み後に変更ファイルパスを報告する

## 手順

### 1. ファイルの決定

`ResearchNotes/ClaudeCodeSession-YYYYMMDD-<TopicSlug>.md` というファイル名にする。
同日・同トピックの既存ノートが既にあれば、新規作成ではなく更新する。

### 2. フォーマット

実例(`ResearchNotes/ClaudeCodeSession-20260703-HerdrDialogueProtocol.md`)を読めるなら参照する。
読めない場合は以下のスケルトンに従う:

```markdown
---
date: YYYY-MM-DD
tags:
  - <プロジェクト名やテーマのケバブケース 3〜6個>
type: research-note
distilled_to:
source: Claude Code session (<モデル名>) on <machine>
context: <personal | work — 出自の判定に従う>
machine: <arch-native | wsl>
---

# <タイトル — 何から何に到達したかが分かる一文>

> Claude Code との対話セッション記録 (YYYY-MM-DD)。
> <セッションの2〜3行サマリー(何を議論し、何を決め、何を作ったか)>

## きっかけ・問題意識
<箇条書き>

## <主要な洞察ごとの見出し(2〜5個。表・引用・コード可)>

## 決定事項・成果物
- ✅ <完了したこと(PR/Issue/ファイルへのリンク付き)>

## 次の一手・宿題
- [ ] <チェックボックス>

## 関連リンク
- <URL、[[wikilink]] を積極的に(既存ノート名と繋ぐ)>
```

#### 親子ノート(worker セッションの供養)

/wtclean の供養から worker の開発過程を昇格させる場合は子ノートとする(実例: `ResearchNotes/ClaudeCodeSession-20260710-Worker-ButtonTokenConvergence.md`):
- 命名: `ResearchNotes/ClaudeCodeSession-YYYYMMDD-Worker-<TopicSlug>.md`
- frontmatter に `parent: "[[親ノート名]]"` を追加し、本文冒頭の引用ブロックに親への wikilink を置く
- 視点の分離: 親 = 司令塔(何を委任しどう判断したか)/ 子 = worker(どう作ったか)
- デイリーノートの New Note Links には親子両方を載せる

### 3. 記録の原則

- LLM 出力の羅列ではなく、「ユーザーとの対話で生まれた判断・設計・学び」を残す
- 引用すべき生ログ(エラーメッセージ・報告原文)は厳選して引用ブロックで載せる
- タグは `Maintenance/TagMaintenance.md` の階層タグ規約(英語・最大2階層)に従う
- 関連リンクは裸のリンクを並べるのではなく、可能なら「なぜ繋がるか」を一言添える

### 4. デイリーノートへのリンク追記

`DailyNotes/YYYY-MM-DD.md`(今日の日付)が存在すれば、`Notes > New Note Links` に以下を Edit で追記する:

```
[[Zettelkasten/ResearchNotes/<ファイル名(拡張子なし)>]]
```

今日のデイリーノートが存在しない場合は、`DailyNotes/` 内で日付が最も新しい既存ノートの同セクションに追記し、どのノートに追記したかを報告する(深夜作業で日付をまたいだケースを想定したフォールバック)。それも見つからない場合のみスキップして報告する。

### 5. 蒸留候補の追記

昇格できそうな知識(Permanent Notes 候補)があれば、デイリーノートの `Distillation > Permanent Notes Candidates` にも1行ずつ追記する。
候補の文言は「問い」の形でもよい(例: 「フォルダは保管の構造、アクセスは宣言する — 一般化できるか?」)。

### 6. 完了報告

作成・更新したノートのパス、追記したデイリーノートのセクション、git 未コミットである旨を報告する。

## 引数

$ARGUMENTS
