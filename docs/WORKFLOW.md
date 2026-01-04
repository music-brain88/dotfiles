# Workflow / ワークフロー

このドキュメントでは、普段の作業内容とワークフローについて説明します。

---

## 📚 Table of Contents

- [Daily Work / 普段の作業内容](#-daily-work--普段の作業内容)
- [Frequently Used Commands / よく使うコマンド](#-frequently-used-commands--よく使うコマンド)
- [Typical Workflow / 典型的なワークフロー](#-typical-workflow--典型的なワークフロー)
- [Future Improvements / 改善したいこと](#-future-improvements--改善したいこと)

---

## 💼 Daily Work / 普段の作業内容

### Editor

| Tool | Description |
|------|-------------|
| Neovim | メインエディタ |

### Development Areas / 開発分野

| Area | Description |
|------|-------------|
| Web開発 | フロントエンド・バックエンド |
| 機械学習（ML） | ML関連の開発 |

### Other Activities / その他の業務

| Activity | Description |
|----------|-------------|
| 技術記事執筆 | Zennなど（今後増える予定） |
| アーキテクチャレビュー | コードレビュー・設計レビュー |
| プロダクト設計 | 全体のアーキテクティング |

---

## ⌨️ Frequently Used Commands / よく使うコマンド

> **Note**: 詳細なキーバインドは [KEYBINDINGS.md](./KEYBINDINGS.md) を参照してください。

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

## 🚀 Future Improvements / 改善したいこと

### Kubernetes関連の効率化

| Goal | Description |
|------|-------------|
| デプロイ・運用管理 | Kubernetesを使った効率化 |
| マニフェスト管理 | 作成・管理を簡単にする仕組み導入 |
| CI/CD統合 | デプロイをパイプラインに統合して自動化 |

### ドキュメント生成の自動化

| Goal | Description |
|------|-------------|
| 自動生成 | rustdoc, Sphinx, mkdocs, TypeDocなど |
| CI連携 | GitHub Actionsでコード変更時に自動生成・更新 |
| 自動公開 | Zenn, GitHub Pagesへの自動公開 |

---

## 🔗 Related Documentation

- [README.md](../README.md) - プロジェクト概要
- [KEYBINDINGS.md](./KEYBINDINGS.md) - キーバインド詳細
- [NEOVIM.md](./NEOVIM.md) - Neovim設定ガイド
- [STRUCTURE.md](./STRUCTURE.md) - ディレクトリ構造
