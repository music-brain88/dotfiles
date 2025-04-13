# dotfiles リポジトリ構造

## .config

### alacritty (Alacrittyターミナルの設定)
    • alacritty.toml - Alacrittyの設定ファイル（フォント、色、キーバインドなど）
### fish (Fishシェルの設定)
    • config.fish - Fishシェルの基本設定（環境変数、エイリアス、プラグイン設定）
    • completions - コマンド補完スクリプト
       • fisher.fish - fisherの補完設定
       • git.fish - gitコマンドの補完設定
       • poetry.fish - Poetryの補完設定
       • pyenv.fish - pyenvの補完設定
### hypr (Hyprlandウィンドウマネージャの設定)
    • hyprland.conf - Hyprlandのメイン設定ファイル
    • hyprlock.conf - ロック画面の設定
    • keybinds.conf - キーバインド設定
    • startup.conf - 起動時に実行するスクリプトの設定
    • window-rules.conf - ウィンドウルール設定
    • scripts
       • notifications.sh - 通知のオン/オフ切り替えスクリプト
       • window-switcher.py - ウィンドウ切り替えスクリプト
    • themes
       • mocha.conf - Catppuccin Mochaテーマの色設定
### i3 (i3ウィンドウマネージャの設定)
    • config - i3の設定ファイル
    • i3-alt-tab.py - Alt+Tabでウィンドウを切り替えるスクリプト
### polybar (Polybarの設定)
    • config.ini - Polybarの基本設定
    • bars.ini - Polybarのバー設定
    • colors.ini - Polybarの色設定
    • modules.ini - Polybarのモジュール設定
    • scripts
       • powermenu.sh - 電源メニュー表示スクリプト
### waybar (Waybarの設定)
    • config.jsonc - Waybarの設定ファイル
    • style.css - Waybarのスタイル設定
### rofi (Rofiランチャーの設定)
    • config.rasi - Rofiの基本設定
    • powermenu
       • confirm.rasi - 確認ダイアログのスタイル
       • full_circle.rasi - パワーメニューのスタイル
       • message.rasi - メッセージダイアログのスタイル
       • styles
          • colors.rasi - 色設定
          • gotham.rasi - Gothamテーマの色設定
    • powermenu.sh - パワーメニューのスクリプト
    • system.sh - システム操作用スクリプト
### eww (Ewwウィジェットの設定)
    • eww.yuck - ウィジェットのレイアウト設定
    • eww.scss - ウィジェットのスタイル設定
 • alacritty (Alacrittyターミナルの設定)
    • alacritty.toml - Alacrittyの設定ファイル（フォント、色、キーバインドなど）
### starship (Starshipプロンプトの設定)
    • starship.toml - Starshipの設定ファイル
### nvim (Neovimの設定)
    • init.lua - Neovimの初期設定
    • coc-settings.json - CoC (Conquer of Completion) の設定
    • dein.toml - deinプラグインマネージャの設定
    • dein_lazy.toml - 遅延ロードするプラグイン設定
    • dashboard.toml - ダッシュボード設定
    • style.toml - カラースキームやアイコン設定
    • copilot.toml - GitHub Copilotの設定
    • ddu_settings.toml - DDU (Denops-based UI) の設定
    • lsp_settings.toml - LSP (Language Server Protocol) の設定
    • treesitter_settings.toml - Treesitterの設定
    • status_line
       • lualine.toml - ステータスライン設定
       • bufferline.toml - バッファライン設定
       • gitsigns.toml - Gitの変更表示設定
    • mini
       • mini.toml - Mini.nvimプラグインの設定
    • dein.toml - dein.vimプラグインマネージャの設定
    • dein_lazy.toml - 遅延読み込みプラグインの設定
    • treesitter_settings.toml - Treesitterの設定
    • status_line
       • lualine.toml - ステータスライン設定
       • bufferline.toml - バッファライン設定
### polybar-themes (Gitサブモジュール)
    • Polybarのテーマ集（外部リポジトリ）
### mpd (Music Player Daemonの設定)
    • mpd.conf - MPDの設定ファイル
### ncmpcpp (MPDクライアントの設定)
    • config - ncmpcppの設定ファイル
📂 alacritty (ターミナルエミュレータの設定)
    • alacritty.toml - Alacrittyの設定ファイル
### bin (ユーティリティスクリプト)
    • deploy.sh - dotfilesのデプロイスクリプト
    • utils
       • setup_base.sh - 基本環境セットアップスクリプト
       • setup_directories.sh - 必要なディレクトリ作成スクリプト
       • setup_fish.sh - Fishシェルセットアップスクリプト
       • setup_git.sh - Git環境セットアップスクリプト
       • setup_neovim.sh - Neovimセットアップスクリプト
       • setup_symlinks.sh - シンボリックリンク作成スクリプト
       • setup_tmux.sh - Tmuxセットアップスクリプト
### github (GitHub Actionsの設定)
    • workflows
       • main.yml - メインのCIワークフロー
       • build-docker-image.yml - Dockerイメージビルド用ワークフロー
       • setup-base.yml - 基本環境セットアップ用ワークフロー
       • setup-env.yml - 環境セットアップ用ワークフロー
       • setup-fish.yml - Fishシェルセットアップ用ワークフロー
       • setup-neovim.yml - Neovimセットアップ用ワークフロー
       • setup-rust.yml - Rust環境セットアップ用ワークフロー
       • setup-terminal.yml - ターミナル環境セットアップ用ワークフロー
       • build-docker-image.yml - Dockerイメージビルド用ワークフロー
    • ISSUE_TEMPLATE
       • Bug_Report.md - バグ報告用テンプレート
       • Feture_Request.md - 機能要望用テンプレート
       • Technical_Issue.md - 技術的課題用テンプレート
### backup (バックアップ関連)
    • pacman
       • pkglist.txt - pacmanパッケージリスト
    • nvidia
       • nvidia.hook - NVIDIAドライバ用のフック設定
### その他の設定ファイル
    • .bashrc - Bashの設定ファイル
    • .bash_profile - Bashのプロファイル設定
    • .bash_aliases - Bashのエイリアス設定
    • .gitconfig - Gitの設定ファイル
    • .gitignore - Gitの無視設定
    • .dockerignore - Dockerの無視設定
    • .mise.toml - miseの設定ファイル
    • .Xmodmap - Xmodmapの設定ファイル
    • .wakatime.cfg.sample - Wakatimeの設定サンプルファイル
