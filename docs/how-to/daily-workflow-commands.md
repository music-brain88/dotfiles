# Daily Workflow Commands / よく使うコマンド

> **Diátaxis:** 🔧 How-to

普段の開発でよく使うコマンド・キーバインドと、典型的な作業の流れをまとめています。日々どんな作業をしているかの背景は [daily-workflow-context.md](../explanation/daily-workflow-context.md) を参照してください。

---

## 📚 Table of Contents

- [Frequently Used Commands / よく使うコマンド](#-frequently-used-commands--よく使うコマンド)
- [Typical Workflow / 典型的なワークフロー](#-typical-workflow--典型的なワークフロー)

---

## ⌨️ Frequently Used Commands / よく使うコマンド

> **Note**: 詳細なキーバインドは [keybindings.md](../reference/keybindings.md) を参照してください。

### Git Operations

| Command / Keybind | Description | 説明 |
|-------------------|-------------|------|
| `git status/add/commit/push/pull` | Basic Git commands | 基本的なGitコマンド |
| `Ctrl+y` | Branch checkout with skim | ブランチ切り替え（skim連携） |
| `delta` | Git diff viewer | 差分表示ツール |
| `gitui` | TUI Git client | Git操作用TUI |

### Docker Operations

| Command / Keybind | Description | 説明 |
|-------------------|-------------|------|
| 基本操作 | Start/Stop/Logs | コンテナの起動・停止・ログ確認 |
| `,d` | Select container with skim | コンテナ選択＆ログ表示（skim連携） |

### Neovim Operations

| Keybind | Description | 説明 |
|---------|-------------|------|
| `,g` | Ripgrep search (via ddu.vim) | 全文検索 |
| LSP keybinds | Code jump, refactoring | コードジャンプ・リファクタリング |
| Copilot | Code generation, review | コード生成・レビュー支援 |

### Tmux Operations

| Operation | Description | 説明 |
|-----------|-------------|------|
| Session管理 | Create, attach, detach | 新規作成・アタッチ・デタッチ |
| Window/Pane | Split, switch | 分割・切り替え |

### Fish Shell Operations

| Command / Keybind | Description | 説明 |
|-------------------|-------------|------|
| `z` | Directory autojump | ディレクトリ移動を効率化 |
| `Ctrl+t` | File search with skim | ファイル検索 |
| `Ctrl+r` | History search with skim | 履歴検索 |
| `Alt+d` | Directory search with skim | ディレクトリ検索 |

### Development Environment

| Tool | Description | 説明 |
|------|-------------|------|
| mise | Version manager | Node.js, Python, Rustなどのバージョン管理 |

---

## 🔄 Typical Workflow / 典型的なワークフロー

### 1. Git操作

```
ブランチ作成・切り替え（skim連携で効率化）
    ↓
最新の変更をpullして同期
```

### 2. コード編集

```
Neovimでコードを書く
    ↓
ripgrep（,g）で全文検索
    ↓
Copilotでコード生成・リファクタリング
    ↓
LSPでコードジャンプ・型チェック・エラー修正
```

### 3. Docker Build

```
Dockerfileを編集
    ↓
コンテナイメージをビルド
    ↓
起動・停止・ログ確認（skim連携 ,d）
```

### 4. テスト実行

```
Dockerコンテナ内でテスト実行
    ↓
結果確認・コード修正
```

### 5. デプロイ

```
テスト通過
    ↓
DockerイメージをレジストリにPush
    ↓
CI/CD（GitHub Actions）で自動デプロイ
```

---

## 🔗 Related Documentation

- [README.md](../../README.md) - プロジェクト概要
- [daily-workflow-context.md](../explanation/daily-workflow-context.md) - 普段の作業内容と今後の展望
- [keybindings.md](../reference/keybindings.md) - キーバインド詳細
- [neovim-config.md](../reference/neovim-config.md) - Neovim設定ガイド
- [directory-structure.md](../reference/directory-structure.md) - ディレクトリ構造
