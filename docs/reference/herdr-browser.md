# herdr-browser Plugin / herdr-browser プラグイン

> **Diátaxis:** 📖 Reference

herdr-browser は、herdr の pane 内に実ブラウザ (Chromium) を描画するプラグインである。エージェントは Chrome DevTools Protocol (CDP) 経由でこのブラウザを操作し、司令塔や人間はその様子を目視できる。

- リポジトリ: [ogulcancelik/herdr-browser](https://github.com/ogulcancelik/herdr-browser)
- 作者は herdr 本体 ([herdrdev/herdr](https://github.com/herdrdev/herdr)) の作者本人であり、実質ファーストパーティである (`id = "official.browser"`)。
- 導入の背景とセキュリティレビュー結果は、Issue [#520](https://github.com/music-brain88/dotfiles/issues/520) に書いてある。
- 上流のリポジトリは 2026-08-22 に deprecated になった。詳細は「上流の deprecated と後継」節に書いてある。

---

## 何をするものか

- herdr の pane に headless Chromium を描画し、Kitty graphics protocol 経由でリアルタイム表示する。
- CDP エンドポイントを公開し、Browser Use / Playwright / Playwright MCP / Chrome DevTools MCP 等の自動化クライアントから操作できる。
- 表示中のペインはマウス・キーボード入力もそのまま Chromium に転送されるため、自動化を見ながら人間が途中で操作を奪うこともできる。
- 想定している運用では、司令塔がエージェントのブラウザ操作を艦隊ビュー越しに監視する「窓」として使う。

## 要件

| 項目 | 内容 |
|------|------|
| herdr | 0.9.2 以上を前提にする (このリポジトリは `flake.nix` の `nixpkgs-herdr` input から 0.9.3 を入れている) |
| OS | Linux または macOS で動く (Windows は未サポート) |
| ランタイム | Bun が要る |
| ブラウザ | Google Chrome または Chromium が要る |
| ターミナル | Kitty graphics protocol に対応している必要がある (WezTerm, kitty, Ghostty 等) |

herdr の版を 0.9.2 以上としている理由は、このリポジトリの設定が 0.9.2 以降の herdr に合わせてあるからである。0.9.2 で herdr 固有の pane graphics API が廃止されたので、このリポジトリはプラグインを `HERDR_BROWSER_TRANSPORT=direct-kitty` で動かし (「herdr 0.9.2 以降の描画経路」節)、セル 1 個のピクセル寸法を `HERDR_BROWSER_CELL_WIDTH` と `HERDR_BROWSER_CELL_HEIGHT` で渡す (「herdr 0.9.2 以降のセル寸法」節)。また、herdr の Kitty graphics は 0.9.0 から既定で有効になったので、`.config/herdr/config.toml` は Kitty graphics の設定を持たない。

このリポジトリでは、Bun を `nix/modules/dev-tools.nix` で入れている。WezTerm 側の Kitty graphics は `.config/wezterm/wezterm.lua` の `enable_kitty_graphics = true` で有効にしてある。

## herdr 0.9.2 以降の描画経路

herdr 0.9.2 以降、プラグインは標準の Kitty graphics を pane の PTY に直接書いて画像を表示する。このリポジトリは、環境変数 `HERDR_BROWSER_TRANSPORT=direct-kitty` でプラグインをこの経路に固定している ([Issue #693](https://github.com/music-brain88/dotfiles/issues/693))。

- herdr v0.9.2 は、herdr 固有の pane graphics API (`pane.graphics.info` / `set` / `clear` / `stream`) を廃止した。これらのメソッドを呼ぶと `unknown_method` が返る。リリースノートは、アプリが標準の Kitty graphics を自分の端末に書き、herdr がそれをネイティブに描画する方式を代わりに示している (herdrdev/herdr#4561)。
- プラグインの viewer (`src/viewer.ts`) は、既定では herdr の API を使う経路 (`herdr-stream`) から順に試す。herdr 0.9.2 以降では、viewer は `pane.graphics.stream` と `pane.graphics.set` の呼び出しに失敗する。viewer はツールバーの直後に次の 3 行の警告を出してから PTY に直接書く経路に落ちる。

  ```
  daemon graphics stream disabled: unknown method: pane.graphics.stream
  pane graphics stream disabled: unknown method: pane.graphics.stream
  pane graphics disabled: unknown method: pane.graphics.set
  ```

- `HERDR_BROWSER_TRANSPORT` が `direct-kitty` のとき、viewer は herdr の API を呼ばずに最初から PTY に直接書く (`src/graphicsTransport.ts`)。この切り替えはプラグインの README には書かれていない。
- `nix/modules/herdr.nix` が `home.sessionVariables` で `HERDR_BROWSER_TRANSPORT = "direct-kitty"` を宣言している。home-manager はこの値を `hm-session-vars.sh` に書き、ログインシェルがそれを読む。herdr サーバーはログインシェル (`fish --login --command herdr`) から起動され、プラグインの pane コマンド (`bun run src/viewer.ts`) はサーバーの環境を継承する。
- 利用者は、この環境変数を変えた後に `mise run nix:switch` を実行する。さらに、herdr サーバーを止めて新しく開いたターミナルから起動し直す必要がある。switch を実行した古いシェルは switch 前の環境のままであり、そのシェルから起動した herdr サーバーも古い環境を継承するので、新しい値は viewer に届かない。古いシェルを使い続けるなら、起動の前に `exec fish` で環境を読み直す。herdr サーバーを止めると全 pane が止まるので、利用者は動いているエージェントが無いときに行う。
- 描画が PTY に直接書く経路で行われていることは、診断行で確かめられる。利用者がプラグイン設定 (`~/.config/herdr/plugins/config/official.browser/browser.json`) に `"showDiagnostics": true` を入れると、viewer は `transport=kitty-pty` で始まる診断行を出す。

## herdr 0.9.2 以降のセル寸法

このリポジトリは、環境変数 `HERDR_BROWSER_CELL_WIDTH=11` と `HERDR_BROWSER_CELL_HEIGHT=22` で、セル 1 個のピクセル寸法を viewer に渡している ([Issue #699](https://github.com/music-brain88/dotfiles/issues/699))。この 2 つを渡さないと、viewer は起動後に 1 回でも描き直した時点で、描き直しを止められなくなる。

### ループが起きる仕組み

viewer (`src/viewer.ts`) は描くたびに、セル寸法を次の順に探す。1 から 3 の結果は 1 秒だけ覚えておき、どれからも得られないときは、描くたびに 4 を行う。

1. herdr の API `pane.graphics.info` を呼ぶ。herdr 0.9.2 はこの API を廃止したので、呼び出しは毎回失敗する。
2. 環境変数 `HERDR_CELL_WIDTH_PX` と `HERDR_CELL_HEIGHT_PX` を読む。herdr 0.9.3 の本体は、この 2 つを plugin の pane に設定しない。
3. 環境変数 `HERDR_BROWSER_CELL_WIDTH` と `HERDR_BROWSER_CELL_HEIGHT` を読む。
4. 端末に `ESC[16t` を送って寸法を問い合わせ、答え (例: `ESC[6;22;11t`) を 80 ms 待つ。

4 の答えは、問い合わせ専用の受け口と、viewer の普段のキー入力の受け口の両方に届く。キー入力の受け口は、答えを Esc キーと文字列 `[6;22;11t` だと読み違える。viewer はそのキーを Chrome に送り、描き直しを要求する。その描き直しが 4 の問い合わせをまた出すので、ループが閉じる。

起動時の最初の描画は、キー入力の受け口を作る前に終わる。そのため、viewer は起動しただけではループに入らず、起動後に 1 回でも描き直したときにループに入る。ループ中の viewer は画像を約 0.13 秒ごとに送り直し、herdr はそのたびに画像を差し替える。herdr には、差し替えの瞬間に一瞬空白が出る未解決のバグ (herdrdev/herdr#3676) があるので、pane がちらついて見える。

### このリポジトリの設定

3 の 2 つの環境変数が得られると、viewer は寸法の取得元を `env-cell` として扱い、`ESC[16t` を送らない。片方だけ設定すると、もう片方はフォールバック値になるので、2 つとも設定する。

| 環境変数 | 値 | 意味 |
|------|----|------|
| `HERDR_BROWSER_CELL_WIDTH` | `11` | セル 1 個の幅 (ピクセル) |
| `HERDR_BROWSER_CELL_HEIGHT` | `22` | セル 1 個の高さ (ピクセル) |

`nix/modules/herdr.nix` が `home.sessionVariables` で、`HERDR_BROWSER_TRANSPORT` と同じ場所にこの 2 つを宣言している。値は native 機の WezTerm の現在のフォント (`.config/wezterm/wezterm.lua` の `HackGen35 Console NF`、`font_size = 14.0`) に合わせたものである。2026-10-11 に、一時的な browser pane で次の結果を確かめた。

| 条件 | キーを送った後の viewer の書き込み |
|------|------------------------------------|
| 2 つの環境変数なし | 毎秒 58〜75 KB が 8 秒間止まらなかった |
| 2 つの環境変数あり | 6 KB を 1 回書いた後、毎秒 80〜128 バイトに戻った |

### 値の測り方

利用者は、次の 2 通りのどちらかでセル寸法を測れる。2 通りの結果は、現在のフォントで一致した。

- herdr の split pane で `ESC[16t` を端末に送り、答え `ESC[6;<高さ>;<幅>t` を読む。現在のフォントでは `ESC[6;22;11t` が返り、高さは 22、幅は 11 である。
- `wezterm cli list --format json` が返す pane のピクセル寸法を、セル数で割る。現在のフォントでは 171×68 セル・1881×1496 ピクセルが返る。幅は 1881÷171=11、高さは 1496÷68=22 になる。

### 測り直しと反映

利用者は、WezTerm のフォントの大きさや DPI を変えたとき、上の 2 通りのどちらかで測り直す。測り直したら、`nix/modules/herdr.nix` の値を書き換える。この値は viewer が画像の大きさをセル数からピクセルへ換算する基準なので、実際のセルの大きさと合わせておく。

変更を反映するには、「herdr 0.9.2 以降の描画経路」節と同じ手順を踏む。利用者は `mise run nix:switch` を実行し、herdr サーバーを止めて新しく開いたターミナルから起動し直す。herdr サーバーの環境が viewer に引き継がれるためである。

## 上流の deprecated と後継

上流の ogulcancelik/herdr-browser は、2026-08-22 のコミット ab5c60b (「chore: deprecate herdr browser」) で deprecated になった。このコミットは `herdr-plugin.toml` を削除し、README に deprecated の警告を入れた。README は後継として [zenbu-labs/terminal-browser](https://github.com/zenbu-labs/terminal-browser) を指名している。

- このリポジトリが使っているプラグインは、deprecated になる前のコミット be6888b (2026-07-28) である。
- terminal-browser は Electron の offscreen rendering で描画する。配布は `curl | bash` か Homebrew で行われ、nixpkgs には収録されておらず、herdr のプラグイン形式でもない。
- terminal-browser への乗り換えは Issue #693 の範囲外であり、別の Issue で扱う。乗り換えると、`device_auth_browser.sh` とこの文書の書き直しが要る。

## プラグイン本体は Nix 管理外

このリポジトリの多くのツールは Nix (Home Manager) で宣言的に管理されているが、herdr-browser プラグイン自体は `herdr plugin install` による**命令的インストール**であり、Nix の管理対象外である。したがって `mise run nix:switch` では導入されず、利用者が「マージ後のインストール手順」節の手順を別途手動で実行する必要がある。

## マージ後のインストール手順

プラグインを新しい機械に入れるとき、利用者は次の手順を順に実行する。

1. `mise run nix:switch` を実行し、bun と、`HERDR_BROWSER_TRANSPORT`・`HERDR_BROWSER_CELL_WIDTH`・`HERDR_BROWSER_CELL_HEIGHT` などの Nix 側の設定を反映する。
2. `herdr server stop` で herdr サーバーを止める。次に、新しく開いた WezTerm のウィンドウ (ログイン fish) から `herdr` を起動する。これで `HERDR_BROWSER_TRANSPORT` とセル寸法の 2 つの環境変数が、サーバーの環境に入る (理由は「herdr 0.9.2 以降の描画経路」節と「herdr 0.9.2 以降のセル寸法」節)。switch を実行した古いシェルから起動すると、サーバーは switch 前の環境を継承するので、この 3 つが viewer に届かない。古いシェルを使い続けるなら、起動の前に `exec fish` で環境を読み直す。
3. `herdr plugin install ogulcancelik/herdr-browser --ref be6888b71cf4eb5939ee79a746bd1a1c22ade046 --yes` を実行し、プラグイン本体をインストールする。上流の既定ブランチは `herdr-plugin.toml` を削除しているので、`--ref` で deprecated になる前のコミットを指定する。`--ref` には完全な 40 桁の commit SHA を書く。短縮形は `git fetch` が remote ref として解決できない。この ref を `git fetch --depth 1` で取得できることは確認したが、`herdr plugin install` の実行自体は未検証である。
4. WezTerm 上で browser pane を開き、描画を実機確認する (例: `herdr plugin pane open --plugin official.browser --entrypoint browser --placement split --direction right --focus`)。

## device-auth 承認フロー

`aws sso login --profile <x>` / `gh auth login -w` / `gcloud auth login` 等の device-auth 系 CLI は、承認用の URL を `$BROWSER` 環境変数 (aws cli v2 は Python `webbrowser` 経由、gh / gcloud も同様) 経由で開く。運用方針「terminal が主・ブラウザは副」に沿って、この承認 1 クリックのためだけに GUI ブラウザが開く摩擦を消すため、`$BROWSER` を herdr-browser の pane へ直行させるラッパースクリプトに差し替えている ([Issue #523](https://github.com/music-brain88/dotfiles/issues/523))。

- ラッパー本体: [`.config/herdr/scripts/device_auth_browser.sh`](../../.config/herdr/scripts/device_auth_browser.sh)
- `nix/modules/herdr.nix` が `~/.local/bin/device_auth_browser` へ symlink 配置し、`home.nix` の `sessionVariables.BROWSER` からそのパスを指す。
- `$BROWSER` はスペース区切りで引数付き指定を解釈しないツールがあるため、単一実行ファイルのラッパーにしてある(`herdr plugin pane open ...` のような複数引数コマンドを直接 `$BROWSER` には書けない)。

### 挙動

ラッパーは、次の順に判定して承認 URL の開き先を決める。

1. **WSL 判定**: `WSL_DISTRO_NAME` が set か `/proc/version` に `microsoft` を含む場合は WSL とみなし、herdr 環境判定に入る前に Windows 側の既定ブラウザへフォールバックする (`wslview` → `rundll32.exe url.dll,FileProtocolHandler` → `explorer.exe` の順で探す)。WSL2 では ConPTY が kitty graphics を剥ぐため herdr-browser は描画不可であり ([運用上の注意](#運用上の注意))、herdr が動いていても pane へは直行させない ([Issue #574](https://github.com/music-brain88/dotfiles/issues/574))。
2. **herdr 環境判定**: `HERDR_ENV=1` なら herdr 内とみなす。`HERDR_ENV` が立っていない場合は、SSH セッション (`SSH_CONNECTION` または `SSH_TTY` が set) でないことを条件に `herdr status server --json` でサーバソケットへの到達性を追加確認する。同一ホストへの SSH セッションはソケットには到達できてしまうため、`HERDR_ENV=1` でない限り必ず GUI ブラウザ (`xdg-open` 等) へフォールバックする。なお GUI フォールバック時は `BROWSER` を unset してから `xdg-open` を呼ぶ (desktop 判定不能な環境で xdg-open の generic モードが `$BROWSER` を参照し、このラッパー自身へ戻る無限ループを防ぐため)。
3. **プラグイン導入済み判定**: `herdr` / `jq` / `bun` が揃っているか、`herdr plugin list --plugin official.browser --json` の結果から `plugin_root` を解決できるかを確認する。`plugin_root` はハードコードせず毎回 CLI から解決する。いずれか欠けていれば GUI へフォールバックする。
4. **pane への navigate**: プラグインの CLI (`bun run <plugin_root>/src/cli.ts views`) で既存 view (可視 pane に紐づくもの) の有無を確認する。
   - 既存 view があれば `bun run <plugin_root>/src/cli.ts open <url>` を実行する(`ensureView()` が既存 view を自動選択して navigate する。`--view` フラグは `connect` 専用で `open` には無い)。
   - 既存 view が無ければ `herdr plugin pane open --plugin official.browser --entrypoint browser --placement overlay --focus --env HERDR_BROWSER_INITIAL_URL=<url>` で新規 pane を overlay 配置(承認だけの一時利用に向く transient/popup 的配置)で開き、初期 URL を渡す。
   - navigate 自体が失敗した場合も GUI ブラウザへフォールバックする。

2 回目以降の承認は、pane 専用の Chrome プロファイル (`~/.local/state/herdr/plugins/official.browser/chrome-profiles/`、0700) に SSO セッションが残るためワンクリックで完了する想定である。新規ログインでパスワード入力が必要になるケース(セッション切れの初回など)で、pane 内のブラウザに直接入力するかどうかは、別途検討事項として残っている。

### 実機確認手順 (マージ後)

このラッパーの実装自体は、コードレビューのみで完結している。実際の承認フローの動作確認にはユーザーの認証情報が必要なため、マージ・`mise run nix:switch` によるライブ反映後にユーザー自身が次の項目を確認する。

1. `mise run nix:switch` で `$BROWSER` 差し替えと symlink を反映する。
2. herdr-browser プラグインが未導入なら [マージ後のインストール手順](#マージ後のインストール手順) を先に実行する。
3. herdr 内 (WezTerm) のシェルから `aws sso login --profile <x>` を実行し、承認 URL が herdr-browser の pane (overlay) 内で開くこと・承認クリックがそのまま完結することを確認する。
4. `gh auth login -w` でも同様に pane 内で承認が完結することを確認する。
5. herdr 外 (例: 素の Alacritty や SSH 接続先) から同じコマンドを実行し、従来どおり GUI ブラウザ (Firefox 等) が開くことを確認する。

## 運用上の注意

- **CDP はローカル限定**: CDP エンドポイントはそのブラウザビューへの完全な制御権を持つ。ループバック (127.0.0.1) に限定し、ネットワークに公開しないこと (プラグイン README にも明記されている運用上の要件である)。
- **WezTerm 専用**: Alacritty は画像プロトコル (Kitty graphics) 非対応であり、設計方針として今後も非搭載の予定である。フォールバック側のターミナルとして使う場合、browser pane はそもそも描画されない。herdr-browser は WezTerm 上でのみ使用する。
- **WSL2 は検証済み・描画不可 (native Arch 専用)**: Windows 11 + WSL2 Arch + Windows 側 WezTerm で 2026-08-05〜07 に検証した結果、browser pane はツールバー (テキスト) のみ表示され、ページ本体 (画像) が描画されない。herdr / plugin / Chromium / 両側の kitty graphics 設定はすべて正常 (plugin daemon の `metrics` でもフレーム送信は正常) で、herdr をバイパスして外側 PTY に直接 kitty graphics エスケープを書いても描画されないことを確認済み。**根本原因は `wsl.exe` と Windows 側ターミナルの間の ConPTY が kitty graphics protocol の APC エスケープ (`ESC _G ... ESC \`) を通さないこと**であり、両側の設定をどう整えても越えられない (参考: [microsoft/terminal#12166](https://github.com/microsoft/terminal/issues/12166))。回避策も検証済みである。wezterm-mux-server + unix domain + `proxy_command` は、GUI 側 codec タイムアウトで断念した。WSLg 上の Linux 版 WezTerm では描画成功まで確認したが、常用導線として重く plugin の IME 未サポートも重なったため、実用は断念した。結論として **WSL 機では herdr-browser を使わない**。この決定に合わせ、device_auth_browser ラッパーは WSL を検知すると Windows 側の既定ブラウザへフォールバックする ([挙動](#挙動) の WSL 判定)。詳細な切り分けログは [Issue #569](https://github.com/music-brain88/dotfiles/issues/569) に書いてある。なお、WSL 機で kitty graphics 系の画像全般が出ない症状も、同じ ConPTY が原因である (browser plugin 固有ではない)。
- **prompt injection のリスクは構造的に残る**: エージェントにブラウザを操作させる以上、Web 由来の prompt injection リスクはこのプラグイン固有の問題ではなく、claude-in-chrome 等の他のブラウザ自動化と同質のものとして残る。

## 関連

- [Issue #520](https://github.com/music-brain88/dotfiles/issues/520) - 導入の背景とセキュリティレビュー結果
- [Issue #523](https://github.com/music-brain88/dotfiles/issues/523) - device-auth 承認フローの $BROWSER ラッパー
- [Issue #569](https://github.com/music-brain88/dotfiles/issues/569) - WSL2 検証結果 (ConPTY により描画不可) の詳細
- [Issue #574](https://github.com/music-brain88/dotfiles/issues/574) - WSL ガード追加 (承認 URL を Windows 側ブラウザへ)
- [Issue #693](https://github.com/music-brain88/dotfiles/issues/693) - herdr 0.9.2 の pane graphics API 廃止への対応 (`HERDR_BROWSER_TRANSPORT=direct-kitty`)
- [Issue #699](https://github.com/music-brain88/dotfiles/issues/699) - viewer が問い合わせの答えをキー入力と読み違えて描き直し続けるので、`HERDR_BROWSER_CELL_WIDTH` と `HERDR_BROWSER_CELL_HEIGHT` で止める。
- [reference/nix-modules.md](./nix-modules.md) - Nixモジュール構成 (bun は dev-tools.nix)
- [explanation/architecture.md](../explanation/architecture.md) - Nix + Symlink ハイブリッドの設計思想
