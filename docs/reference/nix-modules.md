# Nix Modules / Nixモジュール構成

> **Diátaxis:** 📖 Reference

このドキュメントでは、`nix/modules/` 配下のNixモジュール構成を説明します。なぜこのように分割されているかは [architecture.md](../explanation/architecture.md) を参照してください。

---

## 📂 Module Structure

### base.nix

`base.nix` は、最小構成の基本的なシステムパッケージを定義します。curl/wget/cmakeはdev-tools.nixへ、gitはgit.nixへ移動済みです。pkg-config は Nix では入れず、Arch の pkgconf を使います(#740)。
- gnutar, gzip
- protobuf
- mako, libnotify
- wl-clipboard, cliphist, hypridle
- tree, which, file

### rust-tools.nix

`rust-tools.nix` は、Rust開発ツールとCLIツールを定義します。 native crate のビルドに使う pkg-config と openssl は Nix では入れず、Arch の pkgconf と openssl に任せます。Nix の pkg-config は `/usr` を探索できないので、PATH で先に来ると AUR のビルドが Arch のライブラリを見つけられなくなるためです([#740](https://github.com/music-brain88/dotfiles/issues/740))。
- rustup, cargo
- fd, ripgrep, eza, bat
- gitui, tealdeer, hyperfine

### shell.nix

`shell.nix` は、Fish shellとStarshipを設定します。
- Fish shell with plugins (z, bass)
- Starship prompt configuration
- Shell aliases and functions

### git.nix

`git.nix` は、Git の次の項目を設定します。
- User information
- Aliases
- Delta (better diff viewer)
- GitHub CLI (gh)

### tmux.nix

`tmux.nix` は、Tmux の次の項目を設定します。
- Key bindings
- Status bar configuration
- Plugins (sensible, yank, resurrect, etc.)

### herdr.nix

`herdr.nix` は、herdr (agent multiplexer、tmuxの後継) に関する次の 4 つを管理します。
- herdr パッケージ (flake.nix の overlay 経由で新しい nixpkgs から供給)
- `.config/herdr/config.toml` のシンボリックリンク (keybindは旧tmux設定互換)
- device-auth の承認 URL を、herdr の中では terminal-browser の pane に開く `$BROWSER` ラッパー (Issue #523, #701)。terminal-browser 本体は `terminal-browser.nix` が native 機だけに入れる。
- herdr 公式の Claude Code 用フックを、`~/.claude/hooks/herdr-agent-state.sh` に置きます (Issue #755)。仕組みと制約は、次の「Claude Code の pane の復元」に書きます。

#### Claude Code の pane の復元

herdr は、server を止めて起動し直したときに、Claude Code の pane を `claude --resume <id>` で会話ごと再開します。再開に使う session ID は、herdr 公式の Claude Code 用フックが Claude Code の `SessionStart` のたびに herdr へ報告します。フックが入っていないか、フックを呼ぶエントリが `settings.json` に無いと、herdr は session ID を受け取れません。その場合、pane は保存されたディレクトリの普通のシェルとして戻ります。herdr の sidebar と `herdr agent list` は画面の検出で agent を見分けて再開しない pane も `claude` と表示するので、見た目では配線の欠けに気づけません。

公式インストーラ `herdr integration install claude` は `~/.claude/settings.json` に書き込もうとしますが、このリポジトリではこのファイルが home-manager の読み取り専用の symlink なので失敗します。そこでこのリポジトリは、インストーラを Nix のビルドの中で生成器として実行し、生成されたスクリプトを home-manager で配ります。本物の `~/.claude` に対してインストーラを実行しないでください。

次の表は、復元を支える部品と置き場所を並べたものです。

| 部品 | 置き場所 | 役割 |
|---|---|---|
| フックのスクリプトの生成 | `flake.nix` の overlay (`pkgs.herdr-claude-hook`) | ビルド時に `CLAUDE_CONFIG_DIR=$out herdr integration install claude` を実行し、flake で固定した herdr と同じ版のスクリプトを作る。スクリプトの中の `python3` は Nix の python3 の絶対パスに置き換える。単体のビルドは `nix build .#herdr-claude-hook` |
| フックのスクリプトの配置 | `nix/modules/herdr.nix` | 生成したスクリプトを `~/.claude/hooks/herdr-agent-state.sh` に置く。`home.nix` の `".claude"` の recursive マウントの下に、`statusline-command.sh` と同じ形の個別エントリで足す。`.config/claude/` には `hooks/` が無いので、recursive マウントとは衝突しない |
| フックを呼ぶエントリ | `.config/claude/settings.json` の `hooks.SessionStart` | matcher `^(startup\|resume\|clear\|compact\|fork)$` で `bash $HOME/.claude/hooks/herdr-agent-state.sh session` を呼ぶ。手書きで、既存の `inject_core_memory.sh` のエントリとは別のエントリにしてある |
| エントリの検査 | `flake.nix` の `checks.herdr-claude-hook-entries` と `nix/checks/herdr_claude_hook_entries.sh` | インストーラが生成した `settings.json` のエントリと、手書きのエントリを比べる。比べるのは、イベント名・matcher・スクリプトの後ろの引数・timeout の 4 つ。手書きの `SessionStart` に herdr のエントリが無いときも落ちる |

この配線には、次の制約があります。

- **起動フラグは復元されません。** herdr が組み立てる再開コマンドは `claude --resume <id>` だけです。`/wt` の作業者のように `--permission-mode` などのフラグを付けて起動した pane は、再開した後にそのフラグを失います。
- **`herdr integration status` は、フックを呼ぶエントリを見ません。** status はスクリプトの存在と版だけを見て `claude: current (vN)` と表示するので、エントリが無くても正常に見えます。エントリの有無は、上の検査で確かめます。

herdr の版が上がったとき (週次の `flake.lock` の自動更新 PR を含む) は、手元で `mise run nix:check` を実行してください。スクリプトは flake の更新で自動的に新しい版になりますが、エントリは手書きなので、herdr が matcher などを変えるとずれます。ずれていれば `checks.herdr-claude-hook-entries` が生成物と手書きの差分を表示して落ちるので、表示に合わせて `.config/claude/settings.json` を直します。CI の `check` ジョブは `nix flake check --no-build` なので、この検査を実行しません。herdr がスクリプトの形を変えて `python3` の置き換えが当たらなくなったときは、`substituteInPlace --replace-fail` が `pkgs.herdr-claude-hook` のビルドを落とします。このビルドの失敗は、CI の `verify-docker` ジョブでも起きます。

### neovim.nix

`neovim.nix` は、Neovim の次の要素を設定します。
- Language servers (LSP)
- Formatters and linters
- Tree-sitter
- Python environment for Neovim

### dev-tools.nix

`dev-tools.nix` は、次の開発ツールを定義します。
- Container tools (Docker, lazydocker)
- Cloud tools (AWS CLI, Google Cloud SDK, OpenTofu, Ansible) — kubectl/k9s/helmはk8s-tools.nixに集約(「k8s-tools.nix」節参照)
- Database clients
- Language runtimes
- System monitoring tools

### k8s-tools.nix

`k8s-tools.nix` は、Kubernetes / hexhive クラスタの運用ツールを定義します。k8s関連ツールは dev-tools.nix から分離し、このモジュールに集約しています。
- talosctl (Talos Linux CLI、hexhive ノード管理)
- kubectl, k9s (Kubernetes CLI/TUI)
- helm (Kubernetesパッケージ管理)
- sops, age (Secrets暗号化)

### fonts.nix

`fonts.nix` は、次のフォントパッケージを定義します。
- hackgen-nf-font (等幅、ターミナル・エディタ用)
- source-han-sans, source-han-serif (システムUI用)
- noto-fonts-color-emoji (絵文字フォールバック用)

### desktop.nix

`desktop.nix` は、ネイティブArch (Hyprland) 専用のGUI設定群を定義します (WSL profileではimportされません)。
- Hyprland, systemd user units (Hyprlandセッションターゲット)
- Waybar, Wofi, Mako
- WezTerm (メインターミナル), Alacritty (併存期間中のフォールバック)
- MPD, ncmpcpp, fontconfig

### terminal-browser.nix

`terminal-browser.nix` は、device-auth の承認ページを herdr の pane で開くブラウザ terminal-browser に関する次の 4 つを管理します (Issue #701)。`home.nix` は native profile のときだけこのモジュールを読み込みます。WSL 機では ConPTY が kitty graphics を通さないので、terminal-browser は描画できないからです。
- terminal-browser パッケージ (flake.nix の overlay が release の tarball を版と hash で固定して包む)
- スキルの自動リンクを止める `~/.local/state/terminal-browser/skills-choice` (`xdg.stateFile`)
- テレメトリを止める環境変数 `TERMINAL_BROWSER_NO_TELEMETRY` (`home.sessionVariables`)
- 版を上げた後に残る古いプロファイルを消す activation (`cleanTerminalBrowserProfiles`)

設定ごとの理由は [terminal-browser.md](./terminal-browser.md) を参照してください。

### paru.nix

`paru.nix` は、AUR ヘルパー paru のユーザー設定 `.config/paru/paru.conf` を `~/.config/paru/paru.conf` に symlink します (`xdg.configFile`、Issue #743)。この設定は `Include = /etc/paru.conf` で system 側の設定を取り込み、`LocalRepo`・`Chroot`・`SudoLoop` を有効にして、AUR のビルドを devtools の chroot に移します。paru と devtools は OS 層 (pacman) が入れるので、このモジュールはパッケージを入れません。`home.nix` は native profile のときだけこのモジュールを読み込みます。chroot が使う systemd-nspawn が WSL 機で動く保証は無いからです。

symlink を当てる前に system 側で `/etc/pacman.conf` の `[aur]` と devtools を準備する必要があります。手順と順序の理由は [build-aur-packages-in-chroot.md](../how-to/build-aur-packages-in-chroot.md) を参照してください。

### wsl.nix

`wsl.nix` は、WSL固有の設定を定義します (wsl profileでのみ使います)。
- Obsidian vault symlink (実体はWindows側、Cowork/Obsidian Syncの都合)
- WezTerm/Alacritty設定のWindows側への配布 (drift防止、activation時にコピー)

---

## 📝 Notes

### Username Configuration

現在、`home.nix` ではハードコードされたユーザー名 `archie` を使用しています。
利用者は、環境に応じて次の 2 行を変更してください（手順は [customize-your-fork.md](../how-to/customize-your-fork.md) を参照）。

```nix
home.username = "your-username";  # Change this
home.homeDirectory = "/home/your-username";  # And this
```

### Platform Support

現在の設定は `x86_64-linux` をターゲットにしています。
他のプラットフォーム (macOS, ARM) のサポートも可能ですが、追加の設定が必要です。

---

## 🔗 Related Documentation

- [architecture.md](../explanation/architecture.md) - モジュール分割の設計思想
- [customize-your-fork.md](../how-to/customize-your-fork.md) - 新しいモジュールの作成方法
- [directory-structure.md](./directory-structure.md) - ディレクトリ構造
