# セッションログを ResearchNotes へ昇格

Claude Code セッションでの意思決定・洞察・成果物を Obsidian の ResearchNotes に昇格させます。
生ログの全転写ではなく、対話で生まれた判断・設計・学びを厳選して記録する層(層1)を担います。

## 使い方

```
/session-log
/session-log <トピック>
```

- 引数なし: セッションの内容からトピックを自動推定する
- トピックを渡した場合: それを元にファイル名・タイトルを決める

## 前提情報

- Vault: `/home/archie/Documents/Obsidian/Zettelkasten/`(ファイル直接読み書き。Obsidian MCP は使わない)
- 保存先: `ResearchNotes/ClaudeCodeSession-YYYYMMDD-<TopicSlug>.md`(TopicSlug は PascalCase の英語)
- デイリーノート: `DailyNotes/YYYY-MM-DD.md`

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
source: Claude Code session (<モデル名>)
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

### 3. 記録の原則

LLM 出力の羅列ではなく、「ユーザーとの対話で生まれた判断・設計・学び」を残す。
引用すべき生ログ(エラーメッセージ・報告原文)は厳選して引用ブロックで載せる。

### 4. デイリーノートへのリンク追記

`DailyNotes/YYYY-MM-DD.md`(今日の日付)が存在すれば、`Notes > New Note Links` に以下を Edit で追記する:

```
[[Zettelkasten/ResearchNotes/<ファイル名(拡張子なし)>]]
```

デイリーノートが存在しない場合は追記をスキップし、その旨を報告する。

### 5. 蒸留候補の追記

昇格できそうな知識(Permanent Notes 候補)があれば、デイリーノートの `Distillation > Permanent Notes Candidates` にも1行ずつ追記する。

### 6. 完了報告

作成・更新したノートのパスと、追記したデイリーノートのセクションを報告する。

## 引数

$ARGUMENTS
