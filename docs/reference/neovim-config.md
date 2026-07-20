# Neovim Configuration / Neovim設定リファレンス

> **Diátaxis:** 📖 Reference

このドキュメントでは、dotfilesリポジトリのNeovim設定ファイル構成とキーバインドを説明します。プラグイン構成の設計思想については [neovim-plugin-architecture.md](../explanation/neovim-plugin-architecture.md) を参照してください。

---

## 📚 Table of Contents

- [TOML File Structure](#toml-file-structure)
- [Plugin Management (dpp)](#plugin-management-dpp)
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

`vim.lsp.config()` / `vim.lsp.enable()` (Neovim 0.11+ ネイティブAPI) ベース。nvim-lspconfigはサーバー定義データ(`lsp/*.lua`)の提供元としてdeinプラグインのまま維持し、`require('lspconfig')...setup{}`のフレームワーク層は使わない。LSPサーバー本体はすべて`nix/modules/neovim.nix`のextraPackagesから供給される(mason.nvim/mason-lspconfig.nvimは廃止)。

対応言語サーバー:

| Server | Language |
|--------|----------|
| `rust_analyzer` | Rust |
| `pyright` | Python |
| `ts_ls` | TypeScript/JavaScript |

追加ツール:
- **none-ls.nvim**: Prettier等のフォーマッター連携

### copilot.toml - Inline Completion + CopilotChat

GitHub Copilotのインライン補完(copilot.vim + ddc-source-copilot)。CopilotChatはcodecompanion.nvimと並行稼働中で、`:CopilotChat`コマンド経由で引き続き利用可能(専用の`<leader>c*`キーマップはcodecompanion.tomlに付け替え済み)。

### codecompanion.toml - AI Assistant (Multi-agent Hub)

CopilotChat.nvimの後継。[ACP (Agent Client Protocol)](https://github.com/olimorris/codecompanion.nvim)対応のチャット型AIアシスタントを、複数のAIエージェントCLIを束ねる「マルチエージェントハブ」として構成([Epic #447](https://github.com/music-brain88/dotfiles/issues/447) D2/D2b、[Issue #443](https://github.com/music-brain88/dotfiles/issues/443)参照)。

アダプタ構成:

| Adapter | Type | 用途 |
|---------|------|------|
| `copilot` | HTTP | デフォルトアダプタ。既存Copilotサブスクのトークンを利用(APIキー不要)。`<leader>cm`のコミットメッセージ生成はここで`gpt-5.6-luna`に固定 |
| `claude_code` | ACP | 主軸。Claude Code本体(Skills/MCP/CLAUDE.md込み)がチャットの脳になる。要`claude-agent-acp`ラッパー(別途インストール) |
| `gemini_cli` | ACP | 複数CLI併用の実証用。CLI追加が「アダプタ宣言1つ」で完結することを示す |

チャットバッファ内で`ga`キーマップ、または`:CodeCompanionChat <adapter>`でアダプタを切り替え可能。

カスタムプロンプト(prompt library、`g-`接頭辞のaliasで組み込みプロンプトと衝突を回避):
- Explain, Review, Tests, Refactor, Debug
- Optimize, Document, Architecture, Security
- Commit (コミットメッセージ生成、gpt-5.6-luna固定)
- Analyze Buffers (旧`CopilotAnalyzeAllBuffers`/`CopilotAnalyzeSelection`を`#{buffers:all}`/選択範囲コンテキストで代替)

### mini/mini.toml - Mini.nvim Plugins

軽量で高機能なmini.nvimプラグイン群。

| Plugin | Description |
|--------|-------------|
| `mini.indentscope` | インデント範囲の可視化 |
| `mini.comment` | コメントトグル (`gc`) |
| `mini.splitjoin` | 引数の分割・結合 |
| `mini.surround` | テキストを囲む操作 |

---

## 🔌 Plugin Management (dpp)

> dein→dpp移行([#478](https://github.com/music-brain88/dotfiles/pull/478))のフォローアップ([#479](https://github.com/music-brain88/dotfiles/issues/479))。dpp.vimは「本体ミニマル＋拡張分離」の設計思想のため、dein時代と異なりプラグインの取得(インストール・更新)は`dpp-ext-installer`経由の明示的なアクション呼び出しが必要。

### コマンド

| Command | Description |
|---------|-------------|
| `:DppInstall` | 未インストールのプラグインを一括インストール(`dpp-ext-installer#install`のラッパー) |
| `:DppUpdate` | 全プラグインを更新(`dpp-ext-installer#update`のラッパー) |
| `:DppUpdate {plugin...}` | 指定したプラグインのみ更新(スペース区切りで複数指定可) |

両コマンドとも、denopsサーバー起動前(`DenopsReady`前)に実行すると警告を出して中断する(`denops#server#status() != 'running'`をガード)。

### 初回起動時の自動インストール

`init.lua`は`~/.cache/dpp/repos/`配下にクローン済みプラグインが1つもない状態を検知すると、`:DppInstall`相当の処理を通知付きで自動発動する。検知タイミングは以下の2箇所:

- `Dpp:makeStatePost`(state生成直後。主に初回起動でここに引っかかる)
- `DenopsReady`(state生成済みの通常起動時。`repos/`がキャッシュ掃除等で out-of-band に消失していた場合の保険)

自動インストールが完了すると`Dpp:ext:installer:updateDone`イベントで検知し、「Neovimを再起動してプラグインを読み込んでください」と通知する(自動インストールをトリガーした場合のみ表示。手動`:DppUpdate`のたびには出さない)。

### 更新方針(Decision Log D2: 基盤層はrev固定)

denops/ddc/ddu本体・UI層などの基盤層プラグインはTOMLで`rev`を固定しており、dpp-protocol-gitがそのrev指定を尊重するため`:DppUpdate`を無条件に実行してもバージョンは動かない。ただし基盤層プラグインの更新自体は`:DppUpdate`に頼らず、**意図的なrev bump PR**を経由するのが原則([Epic #447](https://github.com/music-brain88/dotfiles/issues/447) Decision Log D2)。`:DppUpdate`は非基盤層プラグイン(rev未指定)の追従更新に使う。

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
| `,r` | Recently used files (MRU) | 最近使ったファイル一覧 |
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

### codecompanion (旧CopilotChatから付け替え)

`<leader>ce`/`cr`/`ct`/`cF`はノーマルモード=バッファ全体、ビジュアルモード=選択範囲を自動判定。CopilotChat自体は`:CopilotChat`コマンドで並行稼働中(キーマップなし)。

| Keybind | Mode | Description | 説明 |
|---------|------|-------------|------|
| `<leader>ce` | n/v | Explain code | コード説明 |
| `<leader>cr` | n/v | Review code | コードレビュー |
| `<leader>ct` | n/v | Generate tests | テスト生成 |
| `<leader>cf` | n | Refactor code | リファクタリング |
| `<leader>cd` | n | Debug help | デバッグヘルプ |
| `<leader>co` | n | Optimize code | 最適化提案 |
| `<leader>cD` | n | Generate documentation | ドキュメント生成 |
| `<leader>ca` | n | Architecture analysis | アーキテクチャ分析 |
| `<leader>cs` | n | Security analysis | セキュリティ分析 |
| `<leader>cm` | n | Generate commit message (gpt-5.6-luna) | コミットメッセージ生成 |
| `<leader>cF` | n/v | Analyze all buffers / selection | 全バッファ/選択範囲分析 |

チャットバッファ内(codecompanion組み込み):

| Keybind | Description | 説明 |
|---------|-------------|------|
| `ga` | Change adapter and model | アダプタ・モデル切替 |
| `gs` | Toggle system prompt | システムプロンプト表示切替 |
| `gd` | Show debug info | デバッグ情報表示 |

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
