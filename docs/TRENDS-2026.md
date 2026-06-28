# Trends 2026 / 2026年トレンド調査レポート

このドキュメントは、**2026年時点のトレンド**を踏まえて dotfiles に追加を検討すべき
**CLI/TUIツール・エージェント向けツール・Claude Code Skills・MCP連携（タスク管理/ノート）**
をまとめた **比較・推奨レポート** です。

> ⚠️ これは「**調査結果と候補一覧**」です。実際の導入（Nixモジュール編集・Skill作成・MCP登録）は
> 本ドキュメントを参照して **後から取捨選択** してください。優先度は High / Med / Low で付与しています。

---

## 📚 Table of Contents

- [0. 既存インベントリ（重複追加の防止）](#0-既存インベントリ重複追加の防止)
- [1. CLI / TUI ツール](#1-cli--tui-ツール)
- [2. エージェント（CLI）が使うツール](#2-エージェントcliが使うツール)
- [3. Claude Code Skills](#3-claude-code-skills)
- [4. タスク管理・ノート連携（MCP）](#4-タスク管理ノート連携mcp)
- [5. 追加方法アペンディックス](#5-追加方法アペンディックス)
- [6. 出典 / Sources](#6-出典--sources)

---

## 0. 既存インベントリ（重複追加の防止）

すでに導入済みのため、**新規追加は不要**（下記の候補から自動的に除外しています）。

| カテゴリ | 導入済みツール | 定義場所 |
|---|---|---|
| モダンCLI | `eza` `bat` `fd` `ripgrep` `procs` `dust` `tealdeer` `hyperfine` `tokei` `jql` `skim` `oxker` | `nix/modules/rust-tools.nix` |
| シェル/プロンプト | `fish` `starship` `zoxide` `atuin` `fzf` `mise` | `nix/modules/shell.nix` |
| Git | `git` `delta` `gh` `gh-dash` `gitui` `tig` `git-crypt` `git-secret` `github-copilot-cli` | `nix/modules/git.nix` |
| マルチプレクサ | `tmux`（+ resurrect/continuum/vim-navigator） | `nix/modules/tmux.nix` |
| コンテナ/クラウド | `docker` `lazydocker` `kubectl` `k9s` `helm` `terraform` `awscli2` `gcloud` | `nix/modules/dev-tools.nix` |
| データ処理 | `jq` `yq` `httpie` `hurl` | `nix/modules/dev-tools.nix` |
| 監視 | `htop` `btop` `bottom` `glances` `ncdu` | `nix/modules/dev-tools.nix` |
| AI | Claude Code（commands: context/pr/create-issue/release-note）, Copilot(nvim+cli), aider context | `.config/claude/`, `.config/copilot/`, `llm/` |

> 💡 既に `skim`（fzf系）・`gitui`/`tig`（git TUI）・`dust`/`procs`（modern unix）を持っているため、
> 同種ツールは「乗り換え候補」または「比較のみ」として扱います。

---

## 1. CLI / TUI ツール

2026年に台頭し、かつ **未導入** のものを厳選。追加先は `nix/modules/*.nix`。

| ツール | 概要 | なぜトレンドか | 現状との関係 | 追加先 | 優先度 |
|---|---|---|---|---|---|
| **yazi** | Rust製・非同期TUIファイラ。画像/PDF/動画サムネプレビュー、タブ、一括リネーム | 2026年の「TUIの目玉」。Ghostty+Yazi+Lazygit の三種の神器として定番化 | 同種なし（nvimのdduはエディタ内専用） | `rust-tools.nix` | **High** |
| **ast-grep (sg)** | ※[セクション2](#2-エージェントcliが使うツール)参照（エージェント用途で最優先） | — | — | `dev-tools.nix` | **High** |
| **lazygit** | Git TUIの最定番。行単位ステージ・対話的rebaseが強力 | コミュニティ最大シェアのGit TUI | `gitui`+`tig` と重複 → **乗り換え候補** | `git.nix` | Med |
| **jujutsu (jj)** | Git互換の新世代VCS。anonymous branch / 自動rebase | 2026年に急成長、Google発 | gitと併用可（学習コスト有） | `git.nix` | Med |
| **gum** | charmbracelet製。シェルスクリプトに入力/選択/スピナー等のUIを付与 | fish/bashスクリプトの対話化に有用 | 既存fish関数の強化に活用可 | `shell.nix` | Med |
| **carapace** | マルチシェル補完エンジン（数百コマンド対応） | fishのネイティブ補完を大幅補強 | fish補完と統合可 | `shell.nix` | Med |
| **difftastic** | 構文認識の構造diff（AST diff） | `delta`（行diff）を補完する別レイヤ | `delta`と併用（用途違い） | `git.nix` | Med |
| **television (tv)** | チャンネル型ファジーファインダTUI | fzfの次世代候補 | `fzf`/`skim`と機能重複 → 比較のみ | `rust-tools.nix` | Low |
| **sd** | `sed`の直感的な代替（Rust） | 正規表現置換が簡単 | `gnused`で代替可 | `rust-tools.nix` | Low |
| **ouch** | 統一圧縮/解凍CLI（zip/tar/gz/zst…） | コマンド差異を吸収 | なし | `rust-tools.nix` | Low |
| **zellij** | tmux代替マルチプレクサ（Rust、レイアウト宣言的） | tmux代替の筆頭 | tmux運用確立済み → **比較のみ** | （見送り推奨） | Low |

**補欠枠（短評）**: `xh`（httpie高速版/Rust） · `doggo`（dig代替） · `gping`（グラフ付きping） · `broot`（ツリーナビ） · `navi`（対話的チートシート） · `mprocs`（複数プロセス並走TUI）。

> 🎯 **最小構成のおすすめ**: まず `yazi`（High）+ `difftastic`（Med）+ `carapace`（Med）の3つから。
> Git TUIを刷新したいなら `gitui`→`lazygit` の乗り換えを検討。

---

## 2. エージェント（CLI）が使うツール

2026年の重要な知見: **「CLIはMCPよりトークン10〜32倍効率・信頼性ほぼ100%」**
（同一タスクでCLIベースのエージェントがMCPベースを全効率指標で上回ったという比較結果）。
→ **エージェントに良いCLIを与えること自体が、Claude Code/aider の性能向上に直結** する。

| ツール | 概要 | エージェントでの価値 | 現状との関係 | 追加先 | 優先度 |
|---|---|---|---|---|---|
| **ast-grep (sg)** | 構造的（AST）コード検索・書換 | ripgrep（テキスト）と層を分け、構造的検索/一括リファクタを正確に実行 | 未導入。`tree-sitter`は有るがCLI検索は別 | `dev-tools.nix` | **High** |
| **comby** | 言語横断の構造的検索＆置換 | ast-grepの代替/補完。テンプレ的な書換に強い | 未導入 | `dev-tools.nix` | Med |
| **semgrep** | ルールベース静的解析/セキュリティ | エージェントによる脆弱性スキャン・規約チェック | 未導入（`shellcheck`/`statix`はある） | `dev-tools.nix` | Med |

**既に十分（追加不要）**: `ripgrep` `fd` `jq` `yq` `gh` `delta` `tree-sitter`。これらはエージェント親和性が高く、基盤として揃っている。

**検索戦略の指針（エージェント向け）**:
> まず **ripgrep** で検索（gitignore尊重・高速・構造化出力）。
> クエリが**構造的**（関数定義・特定の構文パターン）なら **ast-grep** にエスカレーション。
> シンボルや文字列が**未知**な場合のみ semantic 検索に頼る。

---

## 3. Claude Code Skills

現状 `.config/claude/commands/`（`context` / `pr` / `create-issue` / `release-note`）はあるが、
**Skills (`.claude/skills/`) は未導入**。

**Skills と commands の違い**:
- **command**（`/xxx`）= 手動でユーザーが起動するプロンプトテンプレート。
- **Skill** = `SKILL.md` に「いつ使うか（description）」を書き、**モデルが文脈に応じて自動的に発動**する再利用可能な手順書。タスク特化の知識・ワークフローをエージェントへ恒久注入できる。

2026年に評価の高い候補（`.config/claude/skills/<name>/SKILL.md` として作成）:

| Skill | 概要 | 現状との関係 | 優先度 |
|---|---|---|---|
| **test-driven-development** | 実装前にテスト→plan-first/TDDループを強制 | 新規。コーディング品質に直結 | **High** |
| **using-git-worktrees** | 並行作業用の隔離worktreeを賢く作成/管理 | 新規。複数タスク並走に有効 | **High** |
| **mcp-builder** | 高品質なMCPサーバ作成を支援 | セクション4の連携を自作する際に有用 | Med |
| **root-cause-tracing** | エラーを実行経路の根本原因まで追跡 | デバッグ系。新規 | Med |
| **test-fixing** | 失敗テストを検出しパッチ提案 | デバッグ系。新規 | Med |
| **changelog-generator** | gitコミットからユーザー向けchangelog生成 | 既存 `release-note.md` command と重複 → 注記 | Low |

**選定の出発点（キュレーションリスト）**:
- [`hesreallyhim/awesome-claude-code`](https://github.com/hesreallyhim/awesome-claude-code) — 定番の手選びリスト
- [`ComposioHQ/awesome-claude-skills`](https://github.com/ComposioHQ/awesome-claude-skills) — Skill特化リスト

> 💡 既存の `commands/` を Skill に「昇格」させるのも有効（例: `pr` の手順を `SKILL.md` 化し自動発動に）。
> プラグイン面では現状 `code-review` / `github` のみ。必要に応じ `context7`（最新ドキュメント注入）等の追加も検討可。

---

## 4. タスク管理・ノート連携（MCP）

Claude Code の **MCP** はCLIツールとは別レイヤ。dotfilesで**再現可能**にする観点で整理。

### 🗂️ ClickUp（タスク管理）

> ✅ **本リポジトリのClaude Code環境では ClickUp MCP が既に接続済み**（`mcp__ClickUp__*` が利用可能）。
> 下記は dotfiles 側に設定を取り込み、他マシンでも再現するための手順。

- **公式 ClickUp MCP**（HTTPトランスポート / OAuth認証）:
  ```bash
  claude mcp add --transport http clickup https://mcp.clickup.com/mcp
  # 起動後、Claude Code内で /mcp を実行して OAuth 認証
  ```
- **機能**: タスクのCRUD・担当者/優先度/期限付与、Lists/Spaces横断のルーティング、
  タイムトラッキング（開始/停止/履歴）、Docs/コメント横断検索。
- **コミュニティ代替**:
  [`taazkareem/clickup-mcp-server`](https://github.com/taazkareem/clickup-mcp-server)（API token型）,
  [`ClickMongrel`](https://github.com/BuildAppolis/clickmongrel-mcp)（Claude Code特化・タスク同期/時間計測）。
- 優先度: **High**（既に利用中のため、設定の永続化のみ）

### 📝 Obsidian（ノート連携）

2026年の定番は **2層構成**:

1. **Obsidian Local REST APIプラグイン**（[coddingtonbear](https://github.com/coddingtonbear/obsidian-local-rest-api)）を有効化
   - 既定 `https://127.0.0.1:27124`（自己署名証明書）。平文HTTPは `http://127.0.0.1:27123`。
2. **MCPサーバ** [`mcp-obsidian`](https://github.com/MarkusPfundstein/mcp-obsidian)（MarkusPfundstein）
   - `uvx mcp-obsidian` で起動、`OBSIDIAN_API_KEY` を参照。
   ```bash
   claude mcp add --transport http obsidian https://127.0.0.1:27124/mcp/
   # Authorization ヘッダに API キーを設定
   ```
- **機能**: vault一覧 / ディレクトリ一覧 / ファイル取得 / 全文検索 / 追記・編集。
- **代替**:
  [`iansinnott/obsidian-claude-code-mcp`](https://github.com/iansinnott/obsidian-claude-code-mcp),
  [`kanishkez/obsidian-mcp`](https://github.com/kanishkez/obsidian-mcp)。
- 優先度: Med

### 🔐 シークレット管理（重要）

> ⚠️ `OBSIDIAN_API_KEY` やClickUpトークンを **平文でコミットしない** こと。
> 本リポジトリには既に **`git-crypt` / `git-secret`**（`nix/modules/git.nix`）があるので、
> MCP設定ファイル（`.mcp.json` 等）にトークンを書く場合は暗号化対象にするか、
> **環境変数参照**（`${OBSIDIAN_API_KEY}`）にして実値はシェル側で注入する。

---

## 5. 追加方法アペンディックス

後から選定して導入する際の手順。

### Nixツールの追加
1. 該当モジュール（例: `nix/modules/rust-tools.nix`）の `home.packages` に1行追加。
2. アトリビュート名の存在を確認: `nix search nixpkgs yazi`
3. 反映: `mise run nix:switch`

### Claude Code Skill の追加
1. `.config/claude/skills/<name>/SKILL.md` を作成（冒頭YAMLに `name` と `description`＝発動条件を記述）。
   ```markdown
   ---
   name: test-driven-development
   description: Use BEFORE writing implementation code for features or bugfixes.
   ---
   # 手順本文...
   ```
2. `home.nix` のシンボリックリンク設定に `.config/claude/skills` を追加（既存の claude 設定と同様に）。

### MCP の追加
- `.mcp.json` もしくは `.config/claude/settings.json` に記載、または `claude mcp add ...` で登録。
- 認証トークンは上記「シークレット管理」に従い `git-crypt` / 環境変数で保護。

---

## 6. 出典 / Sources

**CLI / TUI トレンド**
- [9 Modern CLI Tools You Should Try in 2026 (Medium)](https://medium.com/the-software-journal/9-modern-cli-tools-you-should-try-in-2026-d561752b1261)
- [12 Modern CLI Tools to Improve Your Workflow in 2026 (Level Up Coding)](https://levelup.gitconnected.com/12-modern-cli-tools-to-improve-your-workflow-in-2026-7e491485614d)
- [New Terminal Tools — Terminal Trove](https://terminaltrove.com/new/)
- [Terminal Power Trio: Ghostty + Yazi + Lazygit (DEV)](https://dev.to/wonderlab/terminal-power-trio-ghostty-yazi-lazygit-for-efficient-development-3iop)
- [The Best TUI Apps for Linux Developers (2026)](https://www.thetechbasket.com/best-tui-apps/)

**エージェント向けCLI**
- [grep, ripgrep, ast-grep, and what AI coding agents actually need](https://agentmako.drhalto.com/blog/grep-ripgrep-ast-grep-vs-typed-tools.html)
- [10 Must-have CLIs for your AI Agents in 2026 (Medium)](https://medium.com/@unicodeveloper/10-must-have-clis-for-your-ai-agents-in-2026-51ba0d0881df)
- [Using ast-grep with AI Tools](https://ast-grep.github.io/advanced/prompting.html)
- [Ripgrep at 10 Years: CLI Tools Still Matter for AI Agents](https://www.buildmvpfast.com/blog/ripgrep-10-years-fast-cli-tools-ai-agents-2026)

**Claude Code Skills**
- [hesreallyhim/awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code)
- [ComposioHQ/awesome-claude-skills](https://github.com/ComposioHQ/awesome-claude-skills)
- [Best Claude Code Skills to Try in 2026 (Firecrawl)](https://www.firecrawl.dev/blog/best-claude-code-skills)

**MCP（タスク管理・ノート）**
- [ClickUp: Connect an AI Assistant to ClickUp's MCP Server](https://developer.clickup.com/docs/connect-an-ai-assistant-to-clickups-mcp-server-1)
- [How to integrate ClickUp MCP with Claude Code (Composio)](https://composio.dev/toolkits/clickup/framework/claude-code)
- [MarkusPfundstein/mcp-obsidian](https://github.com/MarkusPfundstein/mcp-obsidian)
- [coddingtonbear/obsidian-local-rest-api](https://github.com/coddingtonbear/obsidian-local-rest-api)
- [Obsidian MCP Setup 2026: Local REST API Complete Guide](https://mcp.directory/blog/obsidian-mcp-complete-guide-2026)

---

> 📅 調査日: 2026-06-28 ／ 対象: `music-brain88/dotfiles`
> 次のアクション: 本レポートから導入対象を選び、[セクション5](#5-追加方法アペンディックス)の手順で反映してください。
