---
name: context
description: |
  GitHub の Issue / Discussion / PR をコンテキストとして読み込む。
  ユーザーが「Issue #123 を見て」「PR #45 の内容を確認して」「Discussion #67 を読み込んで」
  などと言った時に使用する。
---

# コンテキスト読み込み

GitHub の Issue / Discussion / PR をコンテキストとして読み込みます。

## 使い方

- `123` または `issue 123` → Issue #123
- `discussion 45` または `d 45` → Discussion #45
- `pr 67` または `pull 67` → Pull Request #67

## 手順

### 1. 引数のパース

ユーザーの入力を解析して、タイプと番号を特定する:

- 数字のみ（例: `123`）→ Issue として扱う
- `discussion N` または `d N` → Discussion #N
- `pr N` または `pull N` → Pull Request #N
- `issue N` または `i N` → Issue #N

### 2. リポジトリの特定

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

### 3. コンテンツの取得

**Issue の場合:**
```bash
gh issue view <number> --json title,body,comments,labels,state,author,createdAt
```

**Pull Request の場合:**
```bash
gh pr view <number> --json title,body,comments,reviews,labels,state,author,commits,createdAt
```

**Discussion の場合:**
GraphQL API を使用:
```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    discussion(number: $number) {
      title
      body
      createdAt
      author { login }
      comments(first: 50) {
        nodes {
          body
          createdAt
          author { login }
        }
      }
    }
  }
}' -f owner=<owner> -f repo=<repo> -F number=<number>
```

### 4. コンテキストとして整形

取得した情報を以下の形式で出力:

```markdown
## [Issue/Discussion/PR] #<number>: <title>

**Author:** @<author>
**State:** <state>
**Labels:** <labels>

### 本文

<body>

### コメント

#### @<commenter> (<date>)
<comment body>
```

### 5. 確認

読み込んだコンテキストの要約を表示し、ユーザーに内容を確認させる。
