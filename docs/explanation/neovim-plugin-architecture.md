# Neovim Plugin Architecture / Neovimプラグイン構成

> **Diátaxis:** 💡 Explanation

このドキュメントでは、dotfilesリポジトリのNeovimプラグイン構成の設計について説明します。具体的なTOMLファイル構成やキーバインド一覧は [neovim-config.md](../reference/neovim-config.md) を参照してください。

---

## 🏗️ Plugin Architecture

Neovimの設定は **dpp.vim**(dein.vimの後継)をプラグインマネージャーとして使用し、TOMLファイルベースでモジュール化されています。dpp.vimは「本体ミニマル＋拡張分離」の設計で、本体はstateの生成・読み込みを中心とした最小限の機能に絞られています。TOMLの読み込み(`dpp-ext-toml`)・遅延読み込み(`dpp-ext-lazy`)・プラグインの取得(`dpp-ext-installer` + `dpp-protocol-git`)は、すべて拡張が担います。

### 3つの層

| 層 | 担当 | 役割 |
|----|------|------|
| プラグインマネージャー本体 | Nix(`nix/modules/neovim.nix`) | dpp.vim・denops.vim・dpp拡張群をNix storeに固定し、環境変数(`NVIM_DPP_*` / `NVIM_DENOPS_VIM`)でstoreパスを渡す。`~/.cache`へのコピーやgit cloneはしない |
| 起動・state管理 | `init.lua` | storeパスをruntimepathに追加し、`dpp#min#load_state()`でstateを読む。stateが無ければ`dpp#make_state()`で生成し、プラグインが未取得なら自動インストールする |
| プラグイン宣言 | TOML + `dpp/config.ts` | `config.ts`が14個のTOMLを読み込んでlazy変換し、その結果を`startup.vim` / `state.vim`へ焼き込む。`config.ts`は`dpp#make_state()`実行時にだけDenoで評価され、Neovimの通常起動時には走らない |

どのTOMLをどの区分で読むかを決めているのは`init.lua`ではなく`dpp/config.ts`です。

```
.config/nvim/
├── init.lua                    # エントリーポイント（dppのbootstrap・state管理）
├── dpp/
│   └── config.ts               # TOMLの読み込みリストとlazy区分（state生成時のみ評価）
├── dpp.toml                    # コアプラグイン（起動時読み込み）
├── dpp_lazy.toml               # 遅延読み込みプラグイン
├── ddc_settings.toml           # 補完設定 (ddc.vim)
├── ddu_settings.toml           # ファイラー/検索 (ddu.vim)
├── lsp_settings.toml           # LSP設定
├── copilot.toml                # GitHub Copilot + CopilotChat
├── codecompanion.toml          # AIアシスタント (codecompanion.nvim)
├── treesitter_settings.toml    # シンタックスハイライト
├── style.toml                  # カラースキーム
├── dashboard.toml              # スタートアップ画面
├── hooks/                      # 各プラグインのLuaフック（TOMLのhooks_fileから参照）
├── mini/
│   └── mini.toml               # mini.nvimプラグイン群
└── status_line/
    ├── lualine.toml            # ステータスライン
    ├── bufferline.toml         # バッファライン
    └── gitsigns.toml           # Git差分表示
```

### Loading Strategy

lazy区分は**TOMLファイル単位**で決まります。`dpp/config.ts`の読み込みリストで各ファイルに`lazy: true / false`を指定し、`dpp-ext-toml`の`load`アクションへ`options.lazy`として渡します。遅延グループのファイルでは、各プラグインの`on_event` / `on_ft` / `on_source`等のトリガーが実際の読み込みタイミングを決めます。

| Load Type | Description | Files |
|-----------|-------------|-------|
| **Startup** | 起動時に即座に読み込み | dpp.toml, dashboard.toml, style.toml, copilot.toml, codecompanion.toml, ddu_settings.toml, status_line/*.toml, mini/mini.toml, treesitter_settings.toml |
| **Lazy** | イベント発生時に読み込み | dpp_lazy.toml, lsp_settings.toml, ddc_settings.toml |

プラグインを遅延させたいなら、遅延グループのファイルに置く必要があります。非遅延ファイルに置いたプラグインが遅延プラグインに`depends`すると、依存先まで起動時読み込みに昇格してstateへ焼き込まれ、`on_source`の連鎖が発火しなくなります(`ddc-source-copilot`を`copilot.toml`から`ddc_settings.toml`へ移した [#494](https://github.com/music-brain88/dotfiles/issues/494) の経緯)。

lazy区分もstateに焼き込まれるため、TOMLや`config.ts`の変更を反映するにはstateの再生成が必要です。再生成の経路とプラグインのインストール・更新コマンドは [neovim-config.md の Plugin Management (dpp)](../reference/neovim-config.md#-plugin-management-dpp) を参照してください。

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
