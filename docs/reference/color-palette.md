# Color Palette / カラーパレット

> **Diátaxis:** 📖 Reference

ターミナル環境全体（WezTerm・herdr）で共有する One Dark 系カラーパレットの基準表です。Neovim で使用中の [onedarkpro.nvim](https://github.com/olimorris/onedarkpro.nvim) `onedark` テーマ (`dark_theme = "onedark"`、設定: [`.config/nvim/style.toml`](../../.config/nvim/style.toml)) の正確な値を単一のソースオブトゥルースとし、各設定ファイルに値をコピーして使っています。

背景: [Issue #403](https://github.com/music-brain88/dotfiles/issues/403) — statusline の Myth Dark Pointed 化 (#401 / #402) をきっかけに、ターミナル環境の配色統一に着手しました。

---

## 出典

onedarkpro.nvim の `lua/onedarkpro/themes/onedark.lua`（[GitHub](https://github.com/olimorris/onedarkpro.nvim/blob/main/lua/onedarkpro/themes/onedark.lua)）が定義する base palette と、同梱の WezTerm extra テンプレート（`lua/onedarkpro/extra/wezterm.lua` + `lua/onedarkpro/extra/init.lua` の `add_bright_colors`）が生成する ANSI 16色・bright 色を、当時（2026-07、dein→dpp 移行前）のローカルの dein プラグインキャッシュ（`~/.cache/dein/repos/github.com/olimorris/onedarkpro.nvim/`）から直接確認しました。dpp 移行後の現在、同じソースは `~/.cache/dpp/repos/github.com/olimorris/onedarkpro.nvim/` にあります。

## Base Palette

| Token | Hex | 用途 |
|---|---|---|
| `bg` / `black` | `#282c34` | 背景 |
| `fg` / `white` | `#abb2bf` | 前景 |
| `red` | `#e06c75` | エラー等 |
| `orange` | `#d19a66` | 数値・定数等（**yellow と混同しやすい**） |
| `yellow` | `#e5c07b` | 警告・文字列等 |
| `green` | `#98c379` | 追加・成功等 |
| `cyan` | `#56b6c2` | 型・特殊値等 |
| `blue` | `#61afef` | 関数・情報等 |
| `purple` | `#c678dd` | キーワード・アクセント等 |
| `gray` | `#5c6370` | コメント・非活性 |
| `highlight` | `#e2be7d` | ハイライト（yellow 系の強調） |
| `comment` | `#7f848e` | コメント文字色 |

> `ansi.yellow = #d19a66` のような取り違えは、実際には `orange` の値です。onedark の `yellow` は `#e5c07b` が正しい値です。

## ANSI 16色

次の表は、onedarkpro.nvim が WezTerm 向けに生成する ANSI 16色の値です（`bright_*` は base 色を `helpers.lighten(color, 10)` で明るくした値です）。

| # | 名前 | Normal | Bright |
|---|---|---|---|
| 0 | black | `#282c34` | `#5c6370` |
| 1 | red | `#e06c75` | `#e9969d` |
| 2 | green | `#98c379` | `#b3d39c` |
| 3 | yellow | `#e5c07b` | `#edd4a6` |
| 4 | blue | `#61afef` | `#8fc6f4` |
| 5 | magenta (purple) | `#c678dd` | `#d7a1e7` |
| 6 | cyan | `#56b6c2` | `#7bc6d0` |
| 7 | white | `#abb2bf` | `#c8cdd5` |

カーソルと選択範囲には、`cursor_bg` / `selection_bg` に purple (`#c678dd`) を使い、`cursor_fg` / `selection_fg` に bg (`#282c34`) / fg (`#abb2bf`) を使います。

## 背景色についての判断

`background = #1e2127` は onedarkpro の onedark 値 `#282c34` より暗い値です。WezTerm 設定のコメントにある通り、これは Alacritty 時代から踏襲された値です。ユーザーが意図的に暗くしている可能性があるため、Issue #403 では機械的に上書きしませんでした。

**結論: `#1e2127` を据え置く**（2026-07-11、ユーザー確認済み）。onedark 公式値は `#282c34` です。しかし、ターミナルの背景だけはより暗い値を保つ方が目に優しいので、Neovim 内の onedark 背景とは軽微な差が残ることを許容しました。これは意図的な選択です。他の色（ANSI 16色・herdr のトークン等）は onedarkpro に統一しつつ、背景色のみユーザーの既存の好みを維持します。herdr の `panel_bg` も同じ `#1e2127` に揃え、WezTerm と herdr UI の背景を整合させました。

## 各設定への適用状況

| 設定 | 適用方法 |
|---|---|
| Neovim | onedarkpro.nvim 本体（基準そのもの、変更なし） |
| WezTerm | [`.config/wezterm/wezterm.lua`](../../.config/wezterm/wezterm.lua) の `config.colors` に値をコピー |
| herdr | [`.config/herdr/config.toml`](../../.config/herdr/config.toml) の `[theme]` / `[theme.custom]` に値をコピー（詳細は「herdr のテーマ設定手段 調査結果」節） |
| Alacritty | **対象外**。[#393](https://github.com/music-brain88/dotfiles/issues/393) で WezTerm への移行が進行中のため、Issue #403 のスコープからは除外 |

値の管理方針は「各設定ファイルにコピー + このドキュメントへの出典コメント」です。共通パレット定義ファイルから生成する方式は、Issue #403 のスコープ外としました（将来 Alacritty 移行が完了し、複数ツールの同期が定常的に必要になった時点で再検討します）。

## herdr のテーマ設定手段 調査結果

herdr は `config.toml` に `[theme]` セクションを持ち、以下の手段でカラーをカスタマイズできます（`herdr --default-config` および https://herdr.dev/docs/configuration/ で確認）。

- `[theme] name = "..."` — built-in テーマを選択します。選択できるテーマは `catppuccin` / `catppuccin-latte` / `terminal` / `tokyo-night` / `tokyo-night-day` / `dracula` / `nord` / `gruvbox` / `gruvbox-light` / `one-dark` / `one-light` / `solarized` / `solarized-light` / `kanagawa` / `kanagawa-lotus` / `rose-pine` / `rose-pine-dawn` / `vesper` です。
- `[theme] auto_switch` / `dark_name` / `light_name` — ホスト端末の明暗に追従してテーマを切り替えます（Issue #403 では使っていません）。
- `[theme.custom]` — 個別カラートークンを上書きします。**公式ドキュメントで明示されているトークンは `panel_bg` / `accent` / `red` / `green` / `blue` / `yellow` の6つのみです**（`cyan` / `magenta` / `background` / `foreground` 等の完全なトークン一覧は非公開です）。値は hex / named color / `rgb(r,g,b)` / `reset` などのエイリアスを受け付けます。

herdr は独自のクローズドソースバイナリで配布されており、`[theme.custom]` の全トークン名をソースから確認する手段がありません（Issue #403 の制約上、稼働中デーモンへの設定投入・リロードによる実地確認も対象外にしました）。そのため、Issue #403 では次の方針を採りました。

- `[theme] name = "one-dark"` を採用しました（herdr組み込みの one-dark テーマを土台にします）。
- 文書化済みの `[theme.custom]` トークン（`red` / `green` / `yellow` / `blue` / `accent`）を、onedarkpro の基準値で上書きしました。
- `panel_bg` は「背景色についての判断」節の結論と連動するため、その結論に合わせて設定しました。
- `cyan` / `magenta` など非公開トークンは対象外にしました（herdr 組み込みの `one-dark` テーマの値に委ねます）。

herdr 自体のテーマ設定は、「完全に onedarkpro 値へ統一」までは到達できていません（トークン仕様が非公開なため）。ただし「設定可能」であることは確認できたため、Issue #403 のスコープには含めています。

---

## 🔗 Related Documentation

- [neovim-config.md](./neovim-config.md) — Neovim の設定ファイル構成
- [keybindings.md](./keybindings.md) — herdr のキーバインド
