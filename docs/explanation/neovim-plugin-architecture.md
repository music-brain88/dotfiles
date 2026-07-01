# Neovim Plugin Architecture / Neovimプラグイン構成

> **Diátaxis:** 💡 Explanation

このドキュメントでは、dotfilesリポジトリのNeovimプラグイン構成の設計について説明します。具体的なTOMLファイル構成やキーバインド一覧は [neovim-config.md](../reference/neovim-config.md) を参照してください。

---

## 🏗️ Plugin Architecture

Neovimの設定は **dein.vim** をプラグインマネージャーとして使用し、TOMLファイルベースでモジュール化されています。

```
.config/nvim/
├── init.lua                    # エントリーポイント
├── dein.toml                   # コアプラグイン（起動時読み込み）
├── dein_lazy.toml              # 遅延読み込みプラグイン
├── ddc_settings.toml           # 補完設定 (ddc.vim)
├── ddu_settings.toml           # ファイラー/検索 (ddu.vim)
├── lsp_settings.toml           # LSP設定
├── copilot.toml                # GitHub Copilot + CopilotChat
├── treesitter_settings.toml    # シンタックスハイライト
├── style.toml                  # カラースキーム
├── dashboard.toml              # スタートアップ画面
├── mini/
│   └── mini.toml               # mini.nvimプラグイン群
└── status_line/
    ├── lualine.toml            # ステータスライン
    ├── bufferline.toml         # バッファライン
    └── gitsigns.toml           # Git差分表示
```

### Loading Strategy

| Load Type | Description | Files |
|-----------|-------------|-------|
| **Startup** | 起動時に即座に読み込み | dein.toml, style.toml, ddu_settings.toml |
| **Lazy** | イベント発生時に読み込み | dein_lazy.toml, lsp_settings.toml, ddc_settings.toml |

---

## 🔌 Plugin Details

### Completion Flow

```
User Input
    ↓
ddc.vim (orchestrator)
    ├── ddc-source-lsp (LSP completions)
    ├── ddc-source-copilot (AI suggestions)
    ├── ddc-around (nearby text)
    ├── ddc-file (file paths)
    └── neosnippet (snippets)
    ↓
pum.vim (popup menu)
```

### File Management Flow

```
,m → ddu-filer (floating window + preview)
,g → ddu-ff + rg (full text search)
,b → ddu-ff + buffer (buffer list)
,w → ddu-ff + rg (grep word under cursor)
```

---

## 🔗 Related Documentation

- [neovim-config.md](../reference/neovim-config.md) - TOMLファイル構成・キーバインド一覧
- [architecture.md](./architecture.md) - 全体のアーキテクチャ設計
- [directory-structure.md](../reference/directory-structure.md) - ディレクトリ構造
