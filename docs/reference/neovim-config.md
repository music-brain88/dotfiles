# Neovim Configuration / Neovim設定リファレンス

> **Diátaxis:** 📖 Reference

このドキュメントでは、dotfilesリポジトリのNeovim設定ファイル構成とキーバインドを説明します。プラグイン構成の設計思想については [neovim-plugin-architecture.md](../explanation/neovim-plugin-architecture.md) を参照してください。

---

## 📚 Table of Contents

- [TOML File Structure](#toml-file-structure)
- [Keybindings](#keybindings)
- [Related Files](#related-files)

---

## 📄 TOML File Structure

### dein.toml - Core Plugins

起動時に読み込まれるコアプラグイン。

| Plugin | Description |
|--------|-------------|
| `denops.vim` | Deno runtime for Vim/Neovim plugins |
| `pum.vim` | Popup menu library |
| `lexima.vim` | Auto-close brackets/quotes |
| `winresizer` | Window resize helper |
| `neoterm` | Terminal integration |
| `telescope.nvim` | Fuzzy finder |
| `nvim-colorizer.lua` | Color code highlighter |

### ddc_settings.toml - Completion

ddc.vimベースの補完システム。

| Source | Description |
|--------|-------------|
| `lsp` | Language Server Protocol |
| `around` | 周辺テキスト |
| `file` | ファイルパス |
| `copilot` | GitHub Copilot |
| `neosnippet` | スニペット |
| `cmdline` | コマンドライン |

### ddu_settings.toml - File/Buffer Management

ddu.vimベースのファイラー＆検索システム。

| Mode | Description |
|------|-------------|
| `file` (filer) | ファイルエクスプローラー（フローティングウィンドウ） |
| `text` (ff) | 全文検索 (ripgrep) |
| `buffer` (ff) | バッファ一覧 |
| `word` (ff) | カーソル下の単語でgrep |

### lsp_settings.toml - Language Server

対応言語サーバー:

| Server | Language |
|--------|----------|
| `rust_analyzer` | Rust |
| `pyright` | Python |
| `ts_ls` | TypeScript/JavaScript |

追加ツール:
- **mason.nvim**: LSPサーバーのインストール管理
- **none-ls.nvim**: Prettier等のフォーマッター連携

### copilot.toml - AI Assistant

GitHub Copilot + CopilotChatの設定。

カスタムプロンプト:
- Explain, Review, Tests, Refactor, Debug
- Optimize, Document, Architecture, Security
- Commit (コミットメッセージ生成)

### mini/mini.toml - Mini.nvim Plugins

軽量で高機能なmini.nvimプラグイン群。

| Plugin | Description |
|--------|-------------|
| `mini.indentscope` | インデント範囲の可視化 |
| `mini.comment` | コメントトグル (`gc`) |
| `mini.splitjoin` | 引数の分割・結合 |
| `mini.surround` | テキストを囲む操作 |

---

## ⌨️ Keybindings

### Basic Navigation (init.lua)

| Keybind | Description | 説明 |
|---------|-------------|------|
| `Ctrl+j` | Previous buffer | 前のバッファ |
| `Ctrl+k` | Next buffer | 次のバッファ |
| `tc` | New tab | 新しいタブ |
| `tx` | Close tab | タブを閉じる |
| `tn` | Next tab | 次のタブ |
| `tp` | Previous tab | 前のタブ |

### Terminal (neoterm)

| Keybind | Description | 説明 |
|---------|-------------|------|
| `,rc` | Send file to REPL | ファイルをREPLに送信 |
| `,rl` | Send line to REPL | 行をREPLに送信 |
| `vt` | Toggle terminal | ターミナルトグル |
| `vs` | Open terminal | ターミナルを開く |

### File Explorer (ddu-filer)

`,m` でファイラーを起動。

| Keybind | Description | 説明 |
|---------|-------------|------|
| `Enter` | Open file / Enter directory | ファイルを開く/ディレクトリに入る |
| `h` | Collapse / Preview | 閉じる/プレビュー |
| `..` | Go to parent directory | 親ディレクトリへ |
| `c` | Copy | コピー |
| `d` | Delete | 削除 |
| `mv` | Move | 移動 |
| `r` | Rename | リネーム |
| `t` | New file | 新規ファイル |
| `mk` | New directory | 新規ディレクトリ |
| `Space` | Toggle selection | 選択トグル |
| `o` | Expand/Collapse | 展開/折りたたみ |
| `p` | Preview | プレビュー |
| `q` | Quit | 閉じる |

### Fuzzy Finder (ddu-ff)

| Keybind | Description | 説明 |
|---------|-------------|------|
| `,m` | Open filer | ファイラーを開く |
| `,g` | Full text search (rg) | 全文検索 |
| `,b` | Buffer list | バッファ一覧 |
| `,w` | Grep word under cursor | カーソル下の単語でgrep |

ddu-ff内:

| Keybind | Description | 説明 |
|---------|-------------|------|
| `Enter` | Open file | ファイルを開く |
| `Space` | Toggle selection | 選択トグル |
| `i` | Open filter window | フィルターウィンドウ |
| `q` | Quit | 閉じる |

### LSP

| Keybind | Description | 説明 |
|---------|-------------|------|
| `ge` | Open diagnostic float | 診断フロート表示 |
| `g[` | Go to previous diagnostic | 前の診断へ |
| `g]` | Go to next diagnostic | 次の診断へ |
| `gr` | Find references | 参照一覧 |
| `gd` | Go to definition | 定義へジャンプ |
| `gh` | Hover information | ホバー情報 |
| `gs` | Signature help | シグネチャヘルプ |
| `<Space>rn` | Rename symbol | シンボルをリネーム |
| `<Space>ca` | Code action | コードアクション |
| `<Space>D` | Type definition | 型定義へジャンプ |

ワークスペース管理:

| Keybind | Description |
|---------|-------------|
| `<Space>wa` | Add workspace folder |
| `<Space>wr` | Remove workspace folder |
| `<Space>wl` | List workspace folders |

### Completion (ddc.vim)

| Keybind | Description | 説明 |
|---------|-------------|------|
| `Tab` | Select next completion | 次の補完候補 |
| `Shift+Tab` | Select previous completion | 前の補完候補 |
| `Alt+[` | Copilot previous suggestion | Copilot前の候補 |
| `Alt+]` | Copilot next suggestion | Copilot次の候補 |

### Snippets

| Keybind | Description | 説明 |
|---------|-------------|------|
| `Ctrl+j` | Expand snippet (vsnip) | スニペット展開 |
| `Ctrl+f` | Jump to next placeholder | 次のプレースホルダー |
| `Ctrl+b` | Jump to previous placeholder | 前のプレースホルダー |
| `Ctrl+k` | Expand snippet (neosnippet) | neosnippet展開 |

### CopilotChat

| Keybind | Description | 説明 |
|---------|-------------|------|
| `<leader>ce` | Explain code | コード説明 |
| `<leader>cr` | Review code | コードレビュー |
| `<leader>ct` | Generate tests | テスト生成 |
| `<leader>cf` | Refactor code | リファクタリング |
| `<leader>cd` | Debug help | デバッグヘルプ |
| `<leader>co` | Optimize code | 最適化提案 |
| `<leader>cD` | Generate documentation | ドキュメント生成 |
| `<leader>ca` | Architecture analysis | アーキテクチャ分析 |
| `<leader>cs` | Security analysis | セキュリティ分析 |
| `<leader>cm` | Generate commit message | コミットメッセージ生成 |
| `<leader>cF` | Analyze all buffers / selection | 全バッファ/選択範囲分析 |

### Mini.nvim

#### mini.comment

| Keybind | Description | 説明 |
|---------|-------------|------|
| `gc` | Toggle comment (motion) | コメントトグル（モーション） |
| `gcc` | Toggle line comment | 行コメントトグル |

#### mini.surround

| Keybind | Description | 説明 |
|---------|-------------|------|
| `sa` | Add surrounding | 囲みを追加 |
| `sd` | Delete surrounding | 囲みを削除 |
| `sf` | Find surrounding | 囲みを探す |
| `sF` | Find surrounding (left) | 左側の囲みを探す |
| `sh` | Highlight surrounding | 囲みをハイライト |
| `sr` | Replace surrounding | 囲みを置換 |
| `sn` | Update n lines | n行の囲みを更新 |

---

## 🔗 Related Files

| File | Description |
|------|-------------|
| `.config/nvim/init.lua` | メインエントリーポイント |
| `.config/nvim/*.toml` | プラグイン設定ファイル |
| `nix/modules/neovim.nix` | Nix/Home Manager設定 |

---

## 🔗 Related Documentation

- [neovim-plugin-architecture.md](../explanation/neovim-plugin-architecture.md) - プラグイン構成の設計思想
- [keybindings.md](./keybindings.md) - 全体のキーバインド一覧
- [directory-structure.md](./directory-structure.md) - ディレクトリ構造
- [getting-started.md](../tutorials/getting-started.md) - Nix/Home Manager ガイド
