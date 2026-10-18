# terminal-browser

> **Diátaxis:** 📖 Reference

このリポジトリは、`aws sso login` などの device-auth の承認ページを herdr の pane で開くために、terminal-browser を使う。この文書は、terminal-browser をどう入れ、既定の挙動のどれをなぜ止めているかをまとめる ([Issue #701](https://github.com/music-brain88/dotfiles/issues/701))。

terminal-browser ([zenbu-labs/terminal-browser](https://github.com/zenbu-labs/terminal-browser)、MIT ライセンス) は、Electron の画面外の描画でページを描き、変わった部分だけを kitty graphics で端末へ送るブラウザである。以前は herdr-browser プラグインが同じ役を担っていた。herdr-browser は herdr v0.9.2 の pane graphics API の廃止の後に問題が続き、上流も deprecated にして terminal-browser を後継に挙げたので、#701 で開く先を terminal-browser に替えた。herdr-browser のための設定と文書は、[Issue #702](https://github.com/music-brain88/dotfiles/issues/702) で撤去した。経緯は「herdr-browser からの移行」節に書いてある。

## 構成の一覧

次の表は、このリポジトリが terminal-browser のために置いた設定と、その置き場所を並べたものである。各行の理由は後の節に書いてある。

| 設定 | 置き場所 | 何をするか |
|---|---|---|
| パッケージ | `flake.nix` の overlay (`terminal-browser`) | release の tarball を版と hash で固定し、Nix のパッケージにする |
| 導入 | `nix/modules/terminal-browser.nix` の `home.packages` | native 機だけに入れる (`home.nix` が native のときだけこのモジュールを読む) |
| スキルの自動リンクの拒否 | 同モジュールの `xdg.stateFile."terminal-browser/skills-choice"` | `~/.local/state/terminal-browser/skills-choice` に `no` を置く |
| テレメトリの停止 | 同モジュールの `home.sessionVariables.TERMINAL_BROWSER_NO_TELEMETRY` | 利用状況とクラッシュの報告を止める |
| 古いプロファイルの掃除 | 同モジュールの `home.activation.cleanTerminalBrowserProfiles` | 版を上げた後に残る古いプロファイルを消す |
| herdr の設定 | `.config/herdr/config.toml` の `[terminal]` 節の `kitty_graphics = true` | terminal-browser が herdr の設定に書き込もうとするのを止める |
| WezTerm の設定 | `.config/wezterm/wezterm.lua` の `enable_kitty_graphics = true` | WezTerm で kitty graphics を有効にする (「端末の要件」節) |
| `$BROWSER` ラッパー | `.config/herdr/scripts/device_auth_browser.sh` | herdr の中では承認ページを terminal-browser の pane で開く |

## 導入の仕方

`flake.nix` の overlay は、GitHub の release の `terminal-browser-linux-x64.tar.gz` を `fetchurl` で取り、`autoPatchelfHook` と `makeWrapper` で包む。nixpkgs には terminal-browser が無いので、github-copilot-cli の overlay と同じく、版と hash を flake に固定している。

- tarball の中身は、構成を崩さずに `$out/libexec/terminal-browser/` に置く。同梱の起動スクリプト `bin/terminal-browser` は、自分の置き場所を symlink を辿って求め、その親ディレクトリを `TERMINAL_BROWSER_DIST_ROOT` にして `electron/pixel` (Electron の実行ファイル) に `cli/dist/main.js` を渡す。`$out/bin/terminal-browser` は、この起動スクリプトを呼ぶ `makeWrapper` のラッパーである。
- `autoPatchelfHook` は、`electron/pixel`・`chrome_crashpad_handler`・ネイティブモジュール `pixel.node` などが NEEDED に書いている共有ライブラリを、`buildInputs` の nixpkgs のライブラリにつなぐ。
- Electron は GPU と Vulkan のライブラリ (libGL、vulkan-loader、libdrm など) を NEEDED ではなく dlopen で読む。overlay はこれらを `runtimeDependencies` で rpath に足す。`LD_LIBRARY_PATH` を使わないのは、terminal-browser が起動する `herdr` や `ps` にまで影響させないためである。
- ラッパーは `PATH` の末尾に coreutils と procps を足す。herdr のアダプタが pane と tty の対応を引くときに `tty` と `ps` を使うからである。末尾に足すので、利用者の `PATH` の優先順位は変わらない。

### 版の上げ方

版を上げるときは、利用者が `flake.nix` の overlay の `version` と `hash` の 2 つを書き換える。

1. 上流の release のページで、新しい版の `terminal-browser-linux-x64.tar.gz` の sha256 を確かめる。`gh release view v<版> -R zenbu-labs/terminal-browser --json assets` の `digest` にも載っている。
2. `nix hash convert --hash-algo sha256 --to sri <16 進の sha256>` で SRI 形式に変え、`hash` に書く。
3. `mise run nix:build` で包めることを確かめてから、`mise run nix:switch` で反映する。
4. 版を上げると導入先の store のパスが変わるので、プロファイルも新しくなる。利用者は承認ページで 1 回ログインし直す (「古いプロファイルの掃除」節)。

`terminal-browser upgrade` は使わない。このコマンドは上流のインストーラーを `curl | bash` で実行し、Nix の管理の外に別の一式を入れる。ブラウザの画面に新しい版の案内が出ても、版は上の手順で上げる。

## 入れる機械

terminal-browser は native 機だけに入る。`home.nix` は `profile == "native"` のときだけ `nix/modules/terminal-browser.nix` を読み込むので、WSL 機にはパッケージも環境変数も activation も入らない。WSL 機に入れない理由は、次の節に書いてある。

### WSL 機で描画できない理由

WSL 機では、`wsl.exe` と Windows 側の端末の間にある ConPTY が、kitty graphics の APC エスケープ (`ESC _G ... ESC \`) を通さない ([microsoft/terminal#12166](https://github.com/microsoft/terminal/issues/12166))。そのため、WSL 機の端末には kitty graphics の画像が届かない。この原因はブラウザの種類によらないので、herdr-browser と同じく、terminal-browser も WSL 機では描画できない。WSL 機で kitty graphics の画像全般が出ない症状も、同じ原因である。

- 2026-08-05〜07 の検証 ([Issue #569](https://github.com/music-brain88/dotfiles/issues/569)) では、当時の herdr-browser を使った。このとき、herdr とプラグインと Chromium は正しく動いていて、両側の端末の kitty graphics の設定も正しかった。プラグインはフレームを送っていたが、ページの画像は描画されなかった。herdr を通さずに外側の PTY へ kitty graphics のエスケープを直接書いても、描画されなかった。
- #569 では、回避策を 2 つ試した。wezterm-mux-server と unix domain と `proxy_command` を組む方式は、GUI 側の codec のタイムアウトで断念した。WSLg の上の Linux 版 WezTerm では描画できたが、常用の導線としては重いので採らなかった。
- WSL 機では、ラッパーが承認ページを Windows 側の既定のブラウザで開く (「device_auth_browser.sh の振り分け」節)。

## 端末の要件

terminal-browser は、ページの画像を kitty graphics でしか端末へ送らない。release の bundle (`cli/dist/main.js` と `browser/dist/main.js`) には、sixel などの別の描き方が無い。そのため、端末と herdr の両方が kitty graphics を通す必要がある。

- WezTerm は、kitty graphics を既定で無効にしている。このリポジトリは、`.config/wezterm/wezterm.lua` の `enable_kitty_graphics = true` で有効にしている。
- herdr は、v0.9.0 から、対応する端末で kitty graphics を既定で有効にしている (`terminal.kitty_graphics`)。`.config/herdr/config.toml` にこのキーをあえて書く理由は、「herdr の設定への追記」節に書いてある。
- Alacritty は kitty graphics に対応しておらず、上流は設計の方針として今後も入れない予定である。terminal-browser は WezTerm の上で使う。ラッパーは端末の種類を見ないので、Alacritty の中の herdr で認証すると、ページの描かれない pane が開くはずである (未検証)。

## 既定の挙動を止める設定

terminal-browser の既定の挙動のうち 4 つは、このリポジトリの管理と衝突する。次の 4 つの節は、それぞれの挙動と、止め方と、止める理由を書く。根拠のソースは、release の `cli/dist/main.js.map` と `browser/dist/main.js` で確かめた。

### スキルの自動リンク

terminal-browser は、初回の起動と、版か導入先のパスが変わった後の最初の起動で、自分のスキルを `~/.claude/skills/terminal-browser` と `~/.agents/skills/terminal-browser` に symlink する (`cli/src/setup.ts` の `ensureSetup()`)。`~/.codex/skills` などの親ディレクトリがあれば、そこにもリンクする。Nix で入れると版を上げるたびに store のパスが変わるので、止めないとリンクが毎回作り直される。

`$XDG_STATE_HOME/terminal-browser/skills-choice` (既定は `~/.local/state/terminal-browser/skills-choice`) の中身が `no` なら、terminal-browser はリンクを作らない (`skillsDeclined()`)。home-manager がこのファイルを置く。エージェントに terminal-browser を操作させる用途は今は無いので、スキルは配らない。

このファイルは Nix の store への読み取り専用の symlink になる。`terminal-browser setup` はこのファイルに答えを書き込もうとして失敗するので、実行しない。過去に `terminal-browser setup` がこのファイルを普通のファイルとして書いていても、home-manager は activation を止めずに symlink で置き換える (`force = true`)。

### herdr の設定への追記

terminal-browser の herdr 用のアダプタの `prepare()` は、herdr の中で開くたびに `~/.config/herdr/config.toml` を読む。行全体が `kitty_graphics = true` の行が無ければ、`[experimental]` 節に `kitty_graphics = true` を追記して `herdr server reload-config` を実行する。このリポジトリの `config.toml` は Nix の store への symlink なので、書き込みは権限エラーで黙って失敗する。追記されるはずのキーは、[Issue #693](https://github.com/music-brain88/dotfiles/issues/693) で非推奨として消した `experimental.kitty_graphics` である。

`.config/herdr/config.toml` の `[terminal]` 節に `kitty_graphics = true` を書くと、この検査に一致するので、terminal-browser は追記を試みない。既定値と同じ値なので、herdr の動作は変わらない。

- `terminal.kitty_graphics` が herdr v0.9.3 の正式なキーであることは、`herdr config check` で確かめた。このコマンドは新しい `config.toml` を `config: ok` と判定し、綴りを変えたキーは `unknown config key terminal.kitty_graphicz` と報告した。
- 検査は行全体を正規表現で比べるので、この行の末尾に注釈を付けると一致しなくなる。注釈は上の行に書く。

### テレメトリ

terminal-browser は、利用状況とクラッシュの報告を既定で PostHog に送る。`DO_NOT_TRACK` か `TERMINAL_BROWSER_NO_TELEMETRY` が `1`・`true`・`yes`・`on` のどれかなら、両方の送信が止まる (`browser/dist/main.js` の `telemetryOptedOutByEnv()`)。このリポジトリは `home.sessionVariables` に `TERMINAL_BROWSER_NO_TELEMETRY = "1"` を置く。

- 設定ファイル `~/.config/terminal-browser/settings.json` でも止められる。しかしアプリは実行中にこのファイルを書き換えるので、Nix の読み取り専用の symlink にはしない。
- herdr の pane は herdr サーバーの環境を継承する。`mise run nix:switch` の後は、新しいログインシェルから herdr サーバーを起動し直すまで、pane の中の terminal-browser にこの変数が届かない。

### 古いプロファイルの掃除

terminal-browser は、プロファイルの置き場の名前に、導入先の実パスの sha256 の先頭 8 桁を付ける (`shared/src/paths.ts`)。置き場は次の 4 つにできる。

- `~/.config/terminal-browser-<8 桁>` には、Cookie などの Electron のデータが入る。
- `~/.local/share/terminal-browser-<8 桁>` には、データベースと `install` が入る。
- `~/.local/state/terminal-browser-<8 桁>` には、ログが入る。
- `~/.cache/terminal-browser-<8 桁>` には、favicon が入る (`FAVICONS_DIR`)。2026-10-11 の試験では作られなかったが、ソースはここを置き場にしている。

Nix で入れると版を上げるたびに名前が変わり、古いプロファイルが Cookie ごと残る。

home-manager の activation (`cleanTerminalBrowserProfiles`、`mise run nix:switch` のたびに走る) が、古いプロファイルを消す。activation は `~/.local/share/terminal-browser-<8 桁>/install` に書かれた導入先を読み、次の条件をすべて満たすときだけ、同じ 8 桁を持つ 4 つのディレクトリを消す。

- 名前が `terminal-browser-` と 16 進 8 桁だけである。`terminal-browser-dev-<8 桁>`、`terminal-browser-interop`、`terminal-browser` (設定の置き場) は対象にならない。
- `install` があり、そこに書かれた導入先が `/nix/store/` で始まる。`install` が無いプロファイルは消さない。
- その導入先が、今のパッケージの導入先 (`<store のパス>/libexec/terminal-browser`) と違う。
- プロファイルの lock (`~/.config/terminal-browser-<8 桁>/terminal-browser.lock`) に書かれた PID が生きていない。terminal-browser は起動時にこの lock に自分の PID を書き、終了時に消す。PID が生きていれば、古い版がまだそのプロファイルを使っているので、activation は警告を出してそのプロファイルを残す。利用者が `terminal-browser shutdown` で古い版を止めてから switch し直すと、次の activation が消す。

`/nix/store/` の外を指すプロファイル (手で入れた版や、#701 の前に隔離して入れた試験の版) は消さない。そうしたプロファイルは、利用者が確認を取ってから手で消す。

terminal-browser は、`~/.config` 側の置き場の lock が生きた PID に握られていると、`terminal-browser-<8 桁>-2` から `-32` までの別名の置き場を使う (`browser/src/profile.ts` の `claimProfile()`)。こうした別名の置き場は名前の条件に合わないので、activation は消さない。

削除は home-manager の `run` を通すので、dry-run では消す対象を表示するだけで何も消さない。消すときは、`install` を持つ `~/.local/share` 側を最後に消す。途中で止まっても、次の activation が残りを消す。

## device_auth_browser.sh の振り分け

`$BROWSER` ラッパー `.config/herdr/scripts/device_auth_browser.sh` は、承認ページの開き先を次の順に決める。`nix/modules/herdr.nix` がこのスクリプトを `~/.local/bin/device_auth_browser` に置き、`home.nix` の `BROWSER` がそのパスを指す。

device-auth 系の CLI は、承認ページの URL を `$BROWSER` で開く。aws cli v2 は Python の `webbrowser` を通し、gh と gcloud も同じく `$BROWSER` を見る。`$BROWSER` に空白区切りで引数を書いても、分けて解釈しないツールがある。そのため、このリポジトリはラッパーを、`$BROWSER` に 1 個のパスだけで書ける実行ファイルにしてある ([Issue #523](https://github.com/music-brain88/dotfiles/issues/523))。

1. **WSL 機**: Windows 側の既定のブラウザで開く ([Issue #574](https://github.com/music-brain88/dotfiles/issues/574))。
2. **SSH のセッション**: `SSH_CONNECTION` か `SSH_TTY` があり、`HERDR_ENV=1` が無ければ、GUI ブラウザで開く。
3. **herdr の外**: `HERDR_PANE_ID` が空なら、GUI ブラウザで開く。
4. **herdr の中**: `terminal-browser open "$url" --split right` を実行し、呼び出し元の pane の右に開く。`terminal-browser` が見つからないときと、`open` が失敗したときは、GUI ブラウザで開く。

GUI ブラウザで開くときは、`BROWSER` を unset してから `xdg-open` を呼ぶ。desktop を判定できない環境で `xdg-open` が `$BROWSER` を参照し、このラッパーへ戻るループを防ぐためである。

### herdr の中の判定を HERDR_PANE_ID にした理由

#701 の前のラッパーは、`HERDR_ENV=1` か、SSH でないときに herdr サーバーのソケットが応答することで「herdr の中」と判定していた。#701 では、`HERDR_PANE_ID` が空でないことで判定するように替え、ソケットへの問い合わせと `jq` の依存を消した。

- terminal-browser は、`HERDR_PANE_ID` があるときだけ herdr のアダプタを使う。無ければ、WezTerm などのアダプタで端末そのものを split する。
- 前の判定のままだと、herdr サーバーが動いている間に herdr の外の WezTerm のタブで認証したとき、GUI ブラウザではなく WezTerm の split が開く。判定の条件を terminal-browser がアダプタを選ぶ条件にそろえると、herdr の外の WezTerm 単体では、サーバーの稼働に関係なく GUI ブラウザが開く。
- `HERDR_PANE_ID` が古い値で残っていた場合は、herdr の split が失敗し、`open` の失敗として GUI ブラウザに落ちる。

### 標準出力を捨てる理由

`open` は、開いた後のブラウザの状態を JSON で標準出力に書く。2026-10-11 の試験では、`aws sso login` の pane に約 40 行が流れた。ラッパーは標準出力を `/dev/null` に捨て、失敗の理由が見えるように標準エラーは残す。

### 2 回続けて開いたとき

`open` は、隣に terminal-browser の pane があれば、新しい pane を割らずにその pane にタブとして開く (`--no-merge` か `TERMINAL_BROWSER_NO_MERGE=1` で無効)。2026-10-11 の起動試験で、続けて 2 回 `open --split right` を実行した。2 回目は既存の pane のタブ 2 として開き、pane の数は増えなかった。

## 既知の制限

### Nix 版は GPU を使わずソフトウェア描画で動く

Nix で入れた terminal-browser は、GPU プロセスの初期化に失敗し、Chromium はソフトウェア描画に落ちる。ログには `eglInitialize: Failed to get system egl display` と、`/run/opengl-driver/lib/gbm/dri_gbm.so` が開けないという行が出る。

- 原因は、nixpkgs の libglvnd と mesa が、ドライバを NixOS の `/run/opengl-driver` から探すことである。Arch にはこのディレクトリが無いので、ホストのドライバが見えない。
- native 機の GPU は NVIDIA のプロプライエタリのドライバで動いている。そのため、Nix の mesa に差し替えても GPU は使えない。ホストの NVIDIA のライブラリを読ませる方法 (`__EGL_VENDOR_LIBRARY_DIRS` の指定や nixGL の方式) は、ホストのドライバの版に依存し、更新のたびに壊れうるので採らなかった。`buildFHSEnv` で包んでも Nix の mesa を使う点は同じなので、この問題は解決しない。
- 起動時間への影響は小さい。2026-10-11 に同じ隔離の条件で、`open` を実行してから `terminal-browser action` でページのタイトルを読めるまでを 2 回ずつ測った。Nix 版は 1.70 秒と 1.73 秒、Arch のライブラリで動く試験の版は 1.34 秒と 1.35 秒で、Nix 版が約 0.4 秒遅かった。Nix 版の 1 回の起動では、GPU プロセスの初期化の失敗が 3 回記録された。
- 見直しのきっかけ: 利用者がマージ後の目視の確認で、遅さやちらつきが目立つと判断したら、別の Issue を立てる。その Issue で、ホストの NVIDIA の EGL を読ませる方法と、nixGL の方式を比べ直す。

### その他

GPU のほかに、terminal-browser には次の 3 つの制限がある。

- **スクロールが少し遅い**: herdr の中ではスクロールが少し遅い。描画の回数は制限されていない (`render.fps=display`) ので、herdr が画像を中継する分の遅れと見ている。上流の issue #89 にも同じ報告がある。
- **パスキーとセキュリティキーは未検証**: パスキーやセキュリティキーを要求する認証が Electron の画面外の描画で通るかは、まだ確かめていない。通らない認証に出会ったら、その認証だけ GUI ブラウザで開き、ラッパーに振り分けを足すかを別の Issue で決める。
- **VS Code 系のエディタの設定**: `ensureSetup()` は、スキルとは別に、`~/.config/<名前>/User/globalStorage/state.vscdb` がある VS Code 系のエディタの `settings.json` に `terminal.integrated.enableImages: true` を書く (`cli/src/editors.ts`)。skills-choice ではこの書き込みを止められない。native 機には該当するディレクトリが無いので、今は何も起きない。

## 反映の手順

利用者が native 機で設定を反映するときは、次の順に行う。

1. `mise run nix:switch` を実行する。
2. 新しく開いた WezTerm のウィンドウ (ログイン fish) から herdr サーバーを起動し直す。`TERMINAL_BROWSER_NO_TELEMETRY` を herdr サーバーの環境に入れるためである。switch を実行した古いシェルから起動すると、サーバーは switch 前の環境を継承する。
3. herdr の pane で認証のコマンドを実行し、承認ページが右の pane に開くことを確かめる。

## herdr-browser からの移行

#701 の前は、herdr-browser プラグイン ([ogulcancelik/herdr-browser](https://github.com/ogulcancelik/herdr-browser)、`official.browser`) が承認ページを herdr の pane に開いていた ([Issue #520](https://github.com/music-brain88/dotfiles/issues/520)、[Issue #523](https://github.com/music-brain88/dotfiles/issues/523))。このリポジトリは、herdr-browser を次の順に延命し、撤去した。

1. [Issue #693](https://github.com/music-brain88/dotfiles/issues/693): herdr v0.9.2 が pane graphics API を廃止したので、環境変数 `HERDR_BROWSER_TRANSPORT=direct-kitty` で描画の経路を固定した。
2. [Issue #699](https://github.com/music-brain88/dotfiles/issues/699): viewer がセル寸法の問い合わせの答えをキー入力と読み違えて描き直し続けたので、`HERDR_BROWSER_CELL_WIDTH` と `HERDR_BROWSER_CELL_HEIGHT` でセル寸法を渡して止めた。それでも、ページの裏の変化が描かれない問題は残った。上流は 2026-08-22 に herdr-browser を deprecated にし、後継に terminal-browser を挙げた。
3. [Issue #701](https://github.com/music-brain88/dotfiles/issues/701): 承認ページの開き先を terminal-browser に替えた。切り戻しに備えて、herdr-browser の設定と文書は残した。
4. [Issue #702](https://github.com/music-brain88/dotfiles/issues/702): 利用者は数日 terminal-browser で認証し、問題が無いと確かめた。その後、このリポジトリは herdr-browser のための環境変数 3 つと `bun` と `docs/reference/herdr-browser.md` を撤去した。プラグイン本体は Nix の管理の外にあるので、利用者が各機械で `herdr plugin uninstall official.browser` を実行して外す。

herdr-browser に戻すときは、利用者が #701 と #702 の変更を revert し、プラグインを入れ直す。プラグインの入れ方と延命の設定の詳しい理由は、#702 で消す前の `docs/reference/herdr-browser.md` に書いてある。消したコミットは `git log --diff-filter=D -- docs/reference/herdr-browser.md` で探せ、`git show <そのコミット>^:docs/reference/herdr-browser.md` で消す前の版を読める。

## 関連

- [Issue #701](https://github.com/music-brain88/dotfiles/issues/701): terminal-browser の導入と、この文書の設計の決定
- [Issue #702](https://github.com/music-brain88/dotfiles/issues/702): herdr-browser の設定・依存・文書の撤去
- [Issue #523](https://github.com/music-brain88/dotfiles/issues/523): `$BROWSER` ラッパーの起源
- [Issue #569](https://github.com/music-brain88/dotfiles/issues/569): WSL 機で kitty graphics を描画できない原因
- [nix-modules.md](./nix-modules.md): `nix/modules/terminal-browser.nix` の位置づけ
- 上流のリポジトリ: [zenbu-labs/terminal-browser](https://github.com/zenbu-labs/terminal-browser)
