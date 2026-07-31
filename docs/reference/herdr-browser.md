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

## device-auth 承認フロー

`aws sso login --profile <x>` / `gh auth login -w` / `gcloud auth login` 等の device-auth 系 CLI は、承認用の URL を `$BROWSER` 環境変数 (aws cli v2 は Python `webbrowser` 経由、gh / gcloud も同様) 経由で開く。運用方針「terminal が主・ブラウザは副」に沿って、この承認 1 クリックのためだけに GUI ブラウザが開く摩擦を消すため、`$BROWSER` を herdr-browser の pane へ直行させるラッパースクリプトに差し替えている ([Issue #523](https://github.com/music-brain88/dotfiles/issues/523))。

- ラッパー本体: [`.config/herdr/scripts/device_auth_browser.sh`](../../.config/herdr/scripts/device_auth_browser.sh)
- `nix/modules/herdr.nix` が `~/.local/bin/device_auth_browser` へ symlink 配置し、`home.nix` の `sessionVariables.BROWSER` からそのパスを指す
- `$BROWSER` はスペース区切りで引数付き指定を解釈しないツールがあるため、単一実行ファイルのラッパーにしてある(`herdr plugin pane open ...` のような複数引数コマンドを直接 `$BROWSER` には書けない)

### 挙動

1. **herdr 環境判定**: `HERDR_ENV=1`、または `herdr status server --json` でサーバソケットに到達可能なら herdr 内とみなす。どちらでもなければ (herdr 外・SSH 接続先など) 従来の GUI ブラウザ (`xdg-open` 等) へフォールバックする
2. **プラグイン導入済み判定**: `herdr` / `jq` / `bun` が揃っているか、`herdr plugin list --plugin official.browser --json` の結果から `plugin_root` を解決できるかを確認する。`plugin_root` はハードコードせず毎回 CLI から解決する。いずれか欠けていれば GUI へフォールバックする
3. **pane への navigate**: プラグインの CLI (`bun run <plugin_root>/src/cli.ts views`) で既存 view (可視 pane に紐づくもの) の有無を確認する
   - 既存 view があれば `bun run <plugin_root>/src/cli.ts open <url>` を実行する(`ensureView()` が既存 view を自動選択して navigate する。`--view` フラグは `connect` 専用で `open` には無い)
   - 既存 view が無ければ `herdr plugin pane open --plugin official.browser --entrypoint browser --placement overlay --focus --env HERDR_BROWSER_INITIAL_URL=<url>` で新規 pane を overlay 配置(承認だけの一時利用に向く transient/popup 的配置)で開き、初期 URL を渡す
   - navigate 自体が失敗した場合も GUI ブラウザへフォールバックする

2 回目以降の承認は、pane 専用の Chrome プロファイル (`~/.local/state/herdr/plugins/official.browser/chrome-profiles/`、0700) に SSO セッションが残るためワンクリックで完了する想定。新規ログインでパスワード入力が必要になるケース(セッション切れの初回など)は、pane 内のブラウザで直接入力するかどうかは別途検討事項として残っている。

### 実機確認手順 (マージ後)

このラッパーの実装自体はコードレビューのみで完結しており、実際の承認フローの動作確認にはユーザーの認証情報が必要なため、マージ・`mise run nix:switch` によるライブ反映後にユーザー自身が以下を確認する。

1. `mise run nix:switch` で `$BROWSER` 差し替えと symlink を反映する
2. herdr-browser プラグインが未導入なら [マージ後のインストール手順](#マージ後のインストール手順) を先に実行する
3. herdr 内 (WezTerm) のシェルから `aws sso login --profile <x>` を実行し、承認 URL が herdr-browser の pane (overlay) 内で開くこと・承認クリックがそのまま完結することを確認する
4. `gh auth login -w` でも同様に pane 内で承認が完結することを確認する
5. herdr 外 (例: 素の Alacritty や SSH 接続先) から同じコマンドを実行し、従来どおり GUI ブラウザ (Firefox 等) が開くことを確認する

## 運用上の注意

- **CDP はローカル限定**: CDP エンドポイントはそのブラウザビューへの完全な制御権を持つ。ループバック (127.0.0.1) に限定し、ネットワークに公開しないこと (プラグイン README にも明記されている運用上の要件)
- **WezTerm 専用**: Alacritty は画像プロトコル (Kitty graphics) 非対応であり、設計方針として今後も非搭載の予定。フォールバック側のターミナルとして使う場合、browser pane はそもそも描画されない。herdr-browser は WezTerm 上でのみ使用する
- **WSL は未検証**: Windows 上の WezTerm (WSL2 経由) での動作は帯域面も含めて未検証。native Arch Linux 環境での検証を先に行うこと
- **prompt injection のリスクは構造的に残る**: エージェントにブラウザを操作させる以上、Web 由来の prompt injection リスクはこのプラグイン固有の問題ではなく、claude-in-chrome 等の他のブラウザ自動化と同質のものとして残る

## 関連

- [Issue #520](https://github.com/music-brain88/dotfiles/issues/520) - 導入の背景とセキュリティレビュー結果
- [Issue #523](https://github.com/music-brain88/dotfiles/issues/523) - device-auth 承認フローの $BROWSER ラッパー
- [reference/nix-modules.md](./nix-modules.md) - Nixモジュール構成 (bun は dev-tools.nix)
- [explanation/architecture.md](../explanation/architecture.md) - Nix + Symlink ハイブリッドの設計思想
