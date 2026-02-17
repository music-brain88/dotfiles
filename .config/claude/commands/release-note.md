# 📦 リリースノート充実化

GitHub のリリースドラフトを読み取り、PR の詳細を調査して充実したリリースノートを作成・更新します。

## 使い方

```
/release-note              # 最新のドラフトリリースを充実化
/release-note v0.8.0       # 特定タグのドラフトを充実化
```

## 手順

### 1. ドラフトリリースの特定

引数 (`$ARGUMENTS`) にタグ名が指定されている場合はそのリリースを使用。
指定がない場合は `gh release list` で最新の Draft を探す。

```bash
gh release list --limit 10
```

ドラフトが見つからない場合はユーザーに報告して終了。

### 2. 現在のドラフト内容の取得

```bash
gh release view <tag> --json tagName,name,body,isDraft
```

ドラフトでない場合はユーザーに確認してから続行。

### 3. 前回リリースの特定

`gh release list` から、対象ドラフトの **一つ前** の Latest / Published リリースのタグを特定する。

### 4. コミット一覧の取得

```bash
git log <prev-tag>...<target-tag> --oneline --no-merges
```

各コミットから関連する PR 番号を抽出する。

### 5. PR 詳細の並列調査

各 PR の詳細を `gh pr view <number> --json title,body` で取得する。
**独立した PR は並列で調査** して効率化すること。

### 6. 変更規模の確認

```bash
git diff --shortstat <prev-tag>...<target-tag>
```

### 7. リリースノートの作成

以下の構造でリリースノートを作成する:

```markdown
## 📦 <tag>

<1〜2行のリリース概要サマリー>

## 🎉 What's New

<主要な変更を 3〜5 個ピックアップ。絵文字 + 太字タイトル + 1行説明>

## 🚀 Features

### <機能カテゴリ>: <タイトル> (<PR番号>) @<author>
- <詳細項目（PR body から技術的な要点を抽出）>

## 🐛 Bug Fixes

### <カテゴリ>: <タイトル> (<PR番号>) @<author>
- <修正内容と影響範囲>

## 🔧 Refactoring

### <カテゴリ>: <タイトル> (<PR番号>) @<author>
- <リファクタリング内容>

## ⚠️ Breaking Changes（該当がある場合のみ）

- <破壊的変更の箇条書き>

---

**<N> files changed, <N> insertions(+), <N> deletions(-)**

**Full Changelog:** <compare URL>
```

### 作成のポイント

- **🎉 What's New**: ユーザー向けに「何が嬉しいか」を伝える。技術的な詳細より効果を重視
- **🚀 Features / 🐛 Bug Fixes / 🔧 Refactoring**: PR body から技術的な要点を抽出。コミットメッセージのコピペではなく、内容を理解して説明する
- **⚠️ Breaking Changes**: API の変更、コマンドの削除/リネーム、設定形式の変更など
- **Dependencies セクション**: Features/Fixes と重複する場合は省略
- 自動生成ドラフトに漏れているコミット/PR がないか必ず確認する

### 8. ユーザー確認

作成したリリースノートの内容をプレビュー表示し、ユーザーに確認する。

### 9. ドラフト更新

承認後、`gh release edit <tag> --notes "<content>"` でドラフトを更新する。

## 引数

$ARGUMENTS
