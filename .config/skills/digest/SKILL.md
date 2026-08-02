---
name: digest
description: |
  Obsidian vault の週次ダイジェスト生成（蒸留キューの週次押し出し役）。
  前回ダイジェスト以降の vault の動き — 新着ノート・棚卸し待ちの山・蒸留キュー深度の差分・
  未解決の問い — を500語以内のポインタとして Zettelkasten/Digests/ に保存する。
  ユーザーが「/digest」「今週のダイジェスト作って」「週次まとめて」などと言った時に使う。
  手動トリガー専用（品質が安定するまで自動化しない）。
---

# /digest — 週次ダイジェスト（蒸留キューの週次押し出し役）

/daily が日次の記録と内省、/distill が個々のノートの蒸留を担うのに対し、本スキルは
「今週 vault で何が動いたか」を500語以内のポインタに圧縮し、蒸留セッションの入口を作る。
**運用ルール・パス・骨子の単一の真実は `Zettelkasten/MOC-ObsidianWorkflow.md` の「Digests の設計宣言」**であり、
本スキルの記載と食い違う場合はそちらを優先し、差分を報告する（distill / session-log と同じ構造）。

## 起動方法

- **明示起動のみ**: `/digest`（自動化・スケジュール実行はしない — 品質が安定するまでの段階導入方針）
- 引数で対象期間を上書きできる（例: `/digest 2週間`）

## 実行環境トリアージ

distill と同じ優先順で書き込み手段を選ぶ:
ローカル CLI エージェントはファイル直接読み書き / Claude Desktop・claude.ai は Filesystem MCP /
書き込み手段がなければダイジェスト全文を chat に markdown で出力し、ユーザーが後で取り込む。

## 前提情報

- Vault: `/home/archie/Documents/Obsidian/Zettelkasten/`（WSL でのパス解決は `nix/modules/wsl.nix` の symlink に依存）
- 置き場・命名・frontmatter・骨子の正: MOC「Digests の設計宣言」（`Digests/Digest-YYYYMMDD.md`）
- 蒸留キューの定義（MOC「蒸留状態の宣言」が正）: `distilled_to` が空 **かつ** `triage: candidate`
- Base ビューは GUI 専用。エージェントは frontmatter の Grep 横断で集計する

## 手順

### 1. 対象期間の決定

`Digests/` の最新ノートの `date` の翌日〜今日。初回または3週間以上空いた場合は直近7日に切り詰め、
その旨をダイジェスト冒頭に一行で断る（全履歴の再要約はしない — 期間を絞ることが価値の源泉）。

### 2. 収集（Grep / ファイル走査）

- 期間内の新規ノート: LiteratureNotes（Clip-）・ResearchNotes（ClaudeCodeSession- 含む）・
  FleetingNotes（Idea- / Question-）・ProjectNotes の新規と大きな更新
- 蒸留キュー深度: 現在値と、前回ダイジェスト記載値との差分
- 棚卸し待ち: `triage` 未設定のノート数
- 未解決の問い: `Question-*` で `resolved_to` が空のもの

### 3. 生成（500語以内）

MOC 宣言の骨子に従う: ①主要な新着3〜5件（`[[リンク]]` 付き） ②棚卸し待ちの山の深さ
③キュー深度・前回比差分と蒸留候補の推し1〜2件 ④未解決の問いの棚 ⑤活動が集中したトピックがあれば一行。
ポインタに徹し、本文の要約・再説明で膨らませない。

### 4. 保存

`Zettelkasten/Digests/Digest-YYYYMMDD.md`。frontmatter は宣言に従う
（`type: digest` / `date` / `period_start` / `period_end` / tags: `note-type/digest`・`YYYY-MM`）。

### 5. 導線（soft）

蒸留候補の推しには「/distill でこのまま蒸留に入れる」ことを添える（強制しない）。

## 検疫

本スキルの出力は定義上 LLM 生成物。PermanentNotes への転記・昇格は禁止（vault 運用原則）。
ダイジェストは知識の置き場ではなくポインタ。

## 完了報告

保存パス・キュー深度と差分・推し候補を報告する。コミットはユーザーの日次運用に委ねる（distill と同様）。

## 由来

vault の LiteratureNotes Clip-20260802（Opus 5 + Obsidian リサーチシステム記事）の /digests 概念を、
既存の蒸留パイプラインの「週次押し出し役」として接続したもの（2026-08-02 合意）。
死んだ WeeklyReviews の再興ではない — 蒸留パイプライン設計書の宣言を維持（詳細は MOC「Digests の設計宣言」）。

## 引数

$ARGUMENTS
