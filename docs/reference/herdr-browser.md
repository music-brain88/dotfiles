# herdr-browser Plugin / herdr-browser プラグイン

> **Diátaxis:** 📖 Reference

herdr の pane 内に実ブラウザ (Chromium) を描画し、Chrome DevTools Protocol (CDP) 経由でエージェントに操作させつつ、司令塔や人間がその様子を目視できるようにするプラグイン。

- リポジトリ: [ogulcancelik/herdr-browser](https://github.com/ogulcancelik/herdr-browser)
- 作者は herdr 本体 ([herdrdev/herdr](https://github.com/herdrdev/herdr)) の作者本人であり、実質ファーストパーティ (`id = "official.browser"`)
- 導入の背景・セキュリティレビュー結果は Issue [#520](https://github.com/music-brain88/dotfiles/issues/520) を参照

---

## 何をするものか

- herdr の pane に headless Chromium を描画し、Kitty graphics protocol 経由でリアルタイム表示する
- CDP エンドポイントを公開し、Browser Use / Playwright / Playwright MCP / Chrome DevTools MCP 等の自動化クライアントから操作できる
- 表示中のペインはマウス・キーボード入力もそのまま Chromium に転送されるため、自動化を見ながら人間が途中で操作を奪うこともできる
- 想定運用: 司令塔がエージェントのブラウザ操作を艦隊ビュー越しに監視する「窓」として使う

## 要件

| 項目 | 内容 |
|------|------|
| herdr | 0.7.4 以上 |
| OS | Linux または macOS (Windows 未サポート) |
| ランタイム | Bun |
| ブラウザ | Google Chrome または Chromium |
| ターミナル | Kitty graphics protocol 対応 (WezTerm, kitty, Ghostty 等) |

このリポジトリでは Bun を `nix/modules/dev-tools.nix` に、WezTerm/herdr 側の Kitty graphics 有効化をそれぞれ `.config/wezterm/wezterm.lua` / `.config/herdr/config.toml` に設定済み。

## プラグイン本体は Nix 管理外

このリポジトリの多くのツールは Nix (Home Manager) で宣言的に管理されているが、herdr-browser プラグイン自体は `herdr plugin install` による**命令的インストール**であり、Nix の管理対象外。したがって `mise run nix:switch` では導入されず、下記のインストール手順を別途手動で実行する必要がある。

## マージ後のインストール手順

このリポジトリの変更 (bun 追加・kitty graphics 有効化) がマージ・反映された後、以下を順に実行する。

1. `mise run nix:switch` — bun と Nix 側の設定変更を反映する
2. `herdr server reload-config` — `.config/herdr/config.toml` の `[experimental] kitty_graphics = true` を反映する
3. `herdr plugin install ogulcancelik/herdr-browser --yes` — プラグイン本体をインストールする
4. WezTerm 上で browser pane を開き、描画を実機確認する (例: `herdr plugin pane open --plugin official.browser --entrypoint browser --placement split --direction right --focus`)

## 運用上の注意

- **CDP はローカル限定**: CDP エンドポイントはそのブラウザビューへの完全な制御権を持つ。ループバック (127.0.0.1) に限定し、ネットワークに公開しないこと (プラグイン README にも明記されている運用上の要件)
- **WezTerm 専用**: Alacritty は画像プロトコル (Kitty graphics) 非対応であり、設計方針として今後も非搭載の予定。フォールバック側のターミナルとして使う場合、browser pane はそもそも描画されない。herdr-browser は WezTerm 上でのみ使用する
- **WSL は未検証**: Windows 上の WezTerm (WSL2 経由) での動作は帯域面も含めて未検証。native Arch Linux 環境での検証を先に行うこと
- **prompt injection のリスクは構造的に残る**: エージェントにブラウザを操作させる以上、Web 由来の prompt injection リスクはこのプラグイン固有の問題ではなく、claude-in-chrome 等の他のブラウザ自動化と同質のものとして残る

## 関連

- [Issue #520](https://github.com/music-brain88/dotfiles/issues/520) - 導入の背景とセキュリティレビュー結果
- [reference/nix-modules.md](./nix-modules.md) - Nixモジュール構成 (bun は dev-tools.nix)
- [explanation/architecture.md](../explanation/architecture.md) - Nix + Symlink ハイブリッドの設計思想
