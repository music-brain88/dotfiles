# Issue 作成

GitHub Issue を作成します。

## 使い方

```
/create-issue バグ修正が必要
/create-issue 新機能: ダークモード対応
```

## 手順

### 1. リポジトリの確認

`gh repo view --json nameWithOwner -q .nameWithOwner` で現在のリポジトリを確認する。

### 2. Issue テンプレートの確認

以下のパスでテンプレートを探す:
- `.github/ISSUE_TEMPLATE/`（複数テンプレート）
- `.github/ISSUE_TEMPLATE.md`（単一テンプレート）

テンプレートが存在する場合:
- テンプレート一覧をユーザーに表示
- 適切なテンプレートを選択させる
- 選択したテンプレートの形式に従う

### 3. ラベルの取得

```bash
gh label list --json name,description
```

利用可能なラベルを取得し、Issue の内容に応じて適切なラベルを提案する。

### 4. Issue 内容の作成

ユーザーの入力（`$ARGUMENTS`）を元に:

1. **タイトル**: 簡潔で明確なタイトルを提案
2. **本文**: テンプレートに沿った形式で作成
   - テンプレートがない場合は以下の形式:
     ```markdown
     ## 概要
     <issue の概要>

     ## 詳細
     <詳細な説明>

     ## 期待される動作
     <あれば記載>

     ## 再現手順
     <バグの場合>
     ```
3. **ラベル**: 内容に応じたラベルを提案

### 5. ユーザー確認

作成する Issue の内容をプレビュー表示し、ユーザーに確認する:
- タイトル
- 本文
- ラベル
- アサイン（任意）

### 6. Issue 作成

```bash
gh issue create --title "<title>" --body "<body>" --label "<labels>"
```

作成した Issue の URL を表示する。

## 引数

$ARGUMENTS
