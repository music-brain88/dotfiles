---
name: pr
description: |
  Pull Request を作成または更新する。
  ユーザーが「PR を作成して」「プルリクエストを出して」「変更をレビューに出したい」
  などと言った時に使用する。
---

# Pull Request 作成

Pull Request を作成または更新します。

## 手順

### 1. 既存PRの確認

```bash
gh pr list --head <current-branch>
```

**PRが既に存在する場合:**
- PR番号とURLをユーザーに表示
- `gh pr diff <number>` でPR作成時点からの差分を確認
- 新しいコミットがあれば差分を表示
- ユーザーに以下を確認:
  - PR本文を更新するか
  - 追加のコミットをプッシュするか
  - 何もしないか

**PRが存在しない場合:** 手順2へ進む

### 2. テンプレートの確認

`.github/PULL_REQUEST_TEMPLATE.md` を読み込んでテンプレートの形式を確認し、必ずその形式に従う。

### 3. 変更内容の確認

```bash
git log main..HEAD
git diff main..HEAD
```

### 4. タイトルの決定

Conventional Commits スタイルでタイトルを決定:
- `feat`: 新しい機能
- `fix`: バグ修正
- `docs`: ドキュメントのみの変更
- `chore`: コードに触れない変更
- `refactor`: リファクタリング
- `style`: フォーマットのみの変更
- `test`: テストの追加・修正
- `perf`: パフォーマンス改善
- `ci`: CI設定の変更
- `build`: ビルドシステムの変更

### 5. PR本文の作成

テンプレートの形式に沿ってPR本文を作成する。

### 6. PR作成

```bash
gh pr create --title "<title>" --body "<body>"
```

作成したPRのURLを表示する。
