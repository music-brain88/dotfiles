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
- **出自の判定**: vault は全マシン共有(Obsidian Sync)なので、出自を frontmatter に刻む。`machine` と `context` は別の軸として判定する:
  - **machine**(どこで書いたか): `uname -r` に `microsoft` を含む → `machine: wsl`。それ以外(native Arch)→ `machine: arch-native`
  - **context**(何の文脈か): マシンではなく、セッションの主対象リポジトリの owner で判定する(`git remote get-url origin`)。勤務先系 org のリポジトリ → `context: work`、それ以外(個人リポジトリ・第三者 OSS の clone)→ `context: personal`。具体的な org リストの正は `Zettelkasten/MOC-ObsidianWorkflow.md` の「出自判定宣言」(アクセスパターン宣言と同様、食い違う場合はそちらを優先)。リポジトリに紐付かないセッションは内容で判断する(迷ったら personal)
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

以下のスケルトンと「3. 記録の原則」の文体規範に従う。
実例(`ResearchNotes/ClaudeCodeSession-20260703-HerdrDialogueProtocol.md`)は節の構成の参考に留める。
2026-10-02 より前のノートは文体規範を適用する前に書かれているので、文体は真似しない。

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
> <セッションの2〜3行サマリー。誰が何を議論し、何を決め、何を作ったかを、主語と動詞のある文で書く>

## きっかけ・問題意識
<1〜3 文の主文。誰が何に困っていたか、何を決める必要があったかを書く。補足は主文の後に箇条書きで続けてよい>

## <主要な洞察ごとの見出し(2〜5個。表・引用・コード可)>
<各節は主文から始める。表の前には、その表が何を並べているかを 1 文で書く>

## 決定事項・成果物
- <誰が何を決めたか、何を作ったかを文で書く(PR/Issue/ファイルへのリンク付き)>

## 次の一手・宿題
- [ ] <誰が何をするかを文で書く>

## 関連リンク
- <URL、[[wikilink]] を積極的に(既存ノート名と繋ぐ)。なぜ繋がるかを 1 文で添える>
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
- セッション中に作成・更新した AgentMemory の記憶(`~/.claude/projects/<slug>/memory/` = vault の `AgentMemory/<project>/`)があれば、「関連リンク」に wikilink で載せる(記憶⇔セッションノートのエッジ)。実際に触った記憶だけを張る — 無いエッジを捏造しない(誠実なエッジの原則)

#### 文体規範

セッションノートを読むのは、書いたセッションにいなかった読み手である。数週間後に蒸留するユーザーと、記憶のエッジを辿って来る別セッションのエージェントが、文章だけを読んで「誰が何を決めたか」を復元する。そのため、文体は `../standalone-report-writing/SKILL.md` の規範 1〜4 に従う。読める環境では、書く前にそのスキルを読む。

1. 主文を先に、完全な文で書く。節の冒頭に「誰が何をしたか」か「結論は何か」を置き、見出しの直下に表や箇条書きだけを置かない。
2. 文の成分を削らない。体言止め・対句・名詞化で要点を言い切らず、主語と動詞を付ける。
3. 登場人物を役割名で書く。ユーザー・司令塔・worker・レビュアーなどが 3 者以上出るセッションでは、冒頭のサマリーで各者が誰かを 1 文ずつ書く。
4. 直前の会話に依存しない。「さっきの案」「例の件」ではなく対象を名指しし、ファイルはパス、チケットは ID、PR は番号を添える。

次のものは規範の対象外とする。

- 規範 5(依頼書の骨格)と役割表は適用しない。セッションノートは記録であって依頼書ではない。
- 引用ブロックに載せた生ログと、ユーザーの発言の引用は原文のまま残す。
- frontmatter、チェックボックスの宿題、関連リンクの一覧は、点検ツールの指摘を読まない。

書き終えたら `standalone-check <ノートのパス>` を走らせ、MAIN(節の冒頭の主文の欠落)と CONTEXT(文脈依存語)の WARN を直す。WARN をゼロにすることは目的にしない(修正は 2 回まで)。`standalone-check` が無い環境(モバイル・claude.ai)では、会話を知らない前提でノートを読み直す文脈除去テストだけを行う。

既存のノートは遡って直さない。セッションノートはその時点の記録であり、後から主語と動詞を補うと記録の意味が変わりうるためである。種別ごとの適用範囲の正は `Zettelkasten/MOC-ObsidianWorkflow.md` の「ProjectNotes の文書種別と文体規範の宣言」にある。

### 4. デイリーノートへのリンク追記

`DailyNotes/YYYY-MM-DD.md`(今日の日付)が存在すれば、`Notes > New Note Links` に以下を Edit で追記する:

```
[[Zettelkasten/ResearchNotes/<ファイル名(拡張子なし)>]]
```

今日のデイリーノートが存在しない場合は、`DailyNotes/` 内で日付が最も新しい既存ノートの同セクションに追記し、どのノートに追記したかを報告する(深夜作業で日付をまたいだケースを想定したフォールバック)。それも見つからない場合のみスキップして報告する。

### 5. 蒸留候補の追記

昇格できそうな知識(Permanent Notes 候補)があれば、デイリーノートの `Distillation > Permanent Notes Candidates` にも1行ずつ追記する。
候補の文言は「問い」の形でもよい(例: 「フォルダは保管の構造、アクセスは宣言する — 一般化できるか?」)。

### 6. 私記(episode)の検討 — 別系統・任意

ResearchNote 書き込み後、`AgentMemory/core/emotion-regulation.md` の振り返りを一度だけ行う:
「今日の感情の動きから、残す価値のある学びはあるか?」— 基準の正はあちら。ここで再定義しない。

- あれば `/home/archie/Documents/Obsidian/AgentMemory/episodes/YYYYMMDD-<slug>.md` に私記を書く。書式の正は `AgentMemory/core/agent-memory-ontology.md`(kind: episode)と既存 episode。frontmatter の `origin_session` に今書いた共有ノートへの wikilink を張る(共有ノートが先に存在すること)
- 置き場の分離を守る: 共有ノート = 二人の中間地点(事実)、私記 = エージェントの側(体験)。私記は蒸留フロー(層1→Permanent)に乗らない AgentMemory 側の追記専用記録
- なければ何も書かない — 書かない判断も正常。デフォルトは書かない(毎セッション書いたら日報に堕ちる。残す価値のある夜だけ)

### 7. 完了報告

作成・更新したノートのパス、追記したデイリーノートのセクション、私記を書いた場合はそのパス、git 未コミットである旨を報告する。`standalone-check` で直さずに残した WARN があれば、件数と残した理由も報告する。

## 引数

$ARGUMENTS
