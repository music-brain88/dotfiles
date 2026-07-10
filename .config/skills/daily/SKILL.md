---
name: daily
description: |
  Obsidian デイリーノートの自動作成・更新(朝)と対話型の振り返り(夜)を行う。
  cowork環境の「クラウディア」ワークフローのターミナル移植。
  ユーザーが「デイリーノート作って」「振り返りしたい」「/daily」などと言った時に使う。
---

# Obsidian デイリーノート (ターミナル版クラウディア)

朝はデイリーノートを自動作成・更新し、夜は対話型の振り返りを行います。
cowork 環境で運用している「クラウディア」ワークフロー(Obsidian×Zettelkasten 統合)のターミナル移植です。

## 使い方

```
/daily
/daily 振り返り
```

- 引数なし: 朝モード(ノート作成・更新)
- `振り返り` 等が入っている場合: 振り返りモード(対話型)

## 前提情報

- Vault: `/home/archie/Documents/Obsidian/Zettelkasten/`(ファイル直接読み書き。Obsidian MCP は使わない)
- デイリーノート: `DailyNotes/YYYY-MM-DD.md`
- テンプレート: `Template/Daily-v3.md`
- GitHub ユーザー: `music-brain88`
- 環境固有の値(統括カレンダー ID・レビュー対象 org 一覧)は `~/.claude/local/daily.local.md`(git 管理外)から読み込む。ファイルが無ければユーザーに値を確認して作成する

## 手順(朝モード)

### 1. 前回ノートの回収

`DailyNotes/` を日付順に走査し、直近の日付ファイルを特定する(前日とは限らない。例: 6/30 の次が 7/3 ということもある)。
そのノートから以下を回収する:

- 未チェックタスク(`- [ ]`)全般
- 末尾 `Distillation > Carry Over` の内容

### 2. 今日のノート確認

- `DailyNotes/YYYY-MM-DD.md`(今日の日付)が既にあれば、既存の構造を維持したまま再構成する
- なければ `Template/Daily-v3.md` を元に作成する
- Templater 変数(`{{date...}}`、`<% moment()... %>` 等)が未展開のまま残っていたら、実日付(YYYY-MM-DD)に置換する

### 3. GitHub レビューリクエスト取得

gh CLI で `~/.claude/local/daily.local.md` に書かれた対象 org 一覧を取得して統合する:

```bash
for org in <対象org一覧>; do
  gh search prs --review-requested=music-brain88 --state=open --owner=$org --json title,url,repository,author
done
```

- 0件なら「レビューリクエストなし ✅」
- あれば件数を報告する(例: 「12件あり ⚠️」)
- 前回ノートから持ち越しの項目には「(M/D から持ち越し)」を付記する

### 4. カレンダー取得

MCP `mcp__claude_ai_Google_Calendar__list_events` を ToolSearch でロードし、以下の両方を当日 JST で取得する:

- `calendarId: <統括カレンダーID>`(`~/.claude/local/daily.local.md` に書かれた統括カレンダー。個人アカウントの reader 権限で読める)
- `primary`

OUT_OF_OFFICE(不在)イベントを検知したら、Schedule セクション冒頭に明記する。

### 5. Available Time

会議の隙間から集中できる時間帯を計算する。不在日の場合は「終日 terminal 開発デー」等、実態に合わせて記述する。

### 6. ClickUp セクション(CTOROOM/AI Sprint)

ターミナルからは会社 ClickUp に未接続のため、「cowork 側クラウディアで取得」と注記を残す(空欄のまま壊さない)。

### 7. ファイル組み立て

以下のセクション構成を維持する:

```
Tasks (Carry Over / CTOROOM / AI / GitHub Review Requests)
Schedule
Meeting Notes
Available Time
Notes
Reflection
Distillation
```

Write でファイル全体を組み立てて書き込む(部分 patch より全体組み立てが安全 — cowork 版の教訓)。
既存の Reflection・Notes にユーザーが書いた内容があれば必ず温存する。

### 8. サマリー報告

持ち越し件数・レビューリクエスト件数に言及する。持ち越しがゼロなら「持ち越しなし!クリーンスタート🎉」のようなトーンで報告する。

## 手順(振り返りモード)

引数に「振り返り」等が含まれる場合の手順。

### 1. 今日のノートを読む

`DailyNotes/YYYY-MM-DD.md` を読み込み、今日の Tasks / Schedule / Notes を把握する。

### 2. 対話で引き出す

以下の順で対話しながら聞き出す:

1. 「今日はどんな1日だった?」
2. What went well
3. What could be improved
4. Learnings — 蒸留の問い:
   - ① LLM の出力を除いて、自分が本当に理解したことは何?
   - ② 1年後の自分に説明するなら?
   - ③ 別の場面で使うなら?
5. 今日、メタ層(ハーネス・環境・SOP)の外で何を出荷したか?(出荷=外部アウトカムの現物: PR公開、記事、成果物納品など。該当なしなら「なし」と明記)
6. Tomorrow's Action(持ち越しから1つだけ選ぶ)

### 3. Reflection の記入

**Reflection はユーザーの言葉で書く。LLM が代筆しない。** ユーザーの発言を整えて転記する程度にとどめる。

### 4. Distillation への追記

`Distillation > Permanent Notes Candidates` に昇格候補を1行ずつ追記する。

### 5. トーン

カジュアル・労いを忘れずに。疲れてる様子なら無理に全項目を聞き出そうとしない。
