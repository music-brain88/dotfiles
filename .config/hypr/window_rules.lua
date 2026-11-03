-- ウィンドウルール設定
-- Window rules.
-- 旧 window-rules.conf の windowrule を 1 行ずつ hl.window_rule に写したもの(Hyprland 0.57 の Lua 構文)。
-- match:<条件> は match テーブルのキーに、`<ルール> on` は `<ルール> = true` に、値付きのルールは文字列に対応する。
-- 名前(name)は旧設定でブロック形式だった 3 件だけに付ける。インライン形式だったものは名前なしのまま写す。
-- Each windowrule of the former window-rules.conf maps to one hl.window_rule call (Hyprland 0.57 Lua syntax).
-- match:<prop> -> keys of the match table, `<effect> on` -> `<effect> = true`, valued effects -> strings.
-- Only the three former block-style rules carry a name; former inline rules stay unnamed.

-- ─── ワークスペース割り当て ───────────────────────────
-- 3層構造の設計思想 / Three-layer workspace design:
--   作業台 (ws1〜3) / Workbench: タスクごとに自由に構成する場所。参照用ブラウザやエディタを
--   意図せず連れ去らないよう、固定の windowrule を意図的に置いていない。
--     Freely arranged per task. No fixed windowrule is placed here on purpose, so opening
--     a browser/editor for reference never gets silently yanked to another workspace.
--   詰め所 (ws4〜) / Depot: 通知型で常駐させたいアプリを Go 型（明示的に固定ワークスペースへ
--   送る）でここに集約する。
--     Notification-driven apps that should live in the background are gathered here with
--     a "Go" style rule (explicitly pinned to a fixed workspace).
--   引き出し (special workspaces) / Drawer: 参照アプリを Bring 型（呼び出した時だけ手元に
--   出すオーバーレイ）で扱う層。Super+O / Super+A でどこからでもトグル表示できる（#345）。
--     Reference apps handled as a "Bring" style overlay (summoned only on demand via special
--     workspaces), toggled from anywhere with Super+O / Super+A (#345).
hl.window_rule({ match = { class = "^(slack)$" }, workspace = "4 silent" })
hl.window_rule({ match = { class = "^(discord)$" }, workspace = "4 silent" })
hl.window_rule({ match = { class = "^(spotify)$" }, workspace = "5 silent" })

-- 引き出し: 起動時に named special workspace へ直行させる（Super+O / Super+A でトグル）
-- Drawer: send these reference apps straight to their named special workspace on launch
-- （class 名は実機の hyprctl clients -j で確認済み / class names verified live via hyprctl clients -j）
hl.window_rule({ match = { class = "^(obsidian)$" }, workspace = "special:obsidian silent" })
hl.window_rule({ match = { class = "^(claude-desktop)$" }, workspace = "special:claude silent" })

-- ─── システムユーティリティ（フロート + サイズ + 配置） ──
hl.window_rule({
  name = "pavucontrol",
  match = { class = "^(pavucontrol)$" },
  float = true,
  size = { 800, 600 },
  center = true,
  animation = "slide up",
})

hl.window_rule({
  name = "blueman-manager",
  match = { class = "^(blueman-manager)$" },
  float = true,
  size = { 800, 600 },
  center = true,
  animation = "slide down",
})

hl.window_rule({ match = { class = "^(nm-connection-editor)$" }, float = true })
hl.window_rule({ match = { class = "^(vlc)$" }, float = true })
hl.window_rule({ match = { class = "^(org.kde.polkit-kde-authentication-agent-1)$" }, float = true })
hl.window_rule({ match = { class = "^(file-roller)$" }, float = true })

-- ─── 透明度設定 ─────────────────────────────────────
hl.window_rule({ match = { class = "^(kitty)$" }, opacity = "0.9 0.9" })
hl.window_rule({ match = { class = "^(code)$" }, opacity = "0.95 0.95" })
hl.window_rule({ match = { class = "^(firefox)$" }, opacity = "0.95 0.95" })
hl.window_rule({ match = { class = "^(slack)$" }, opacity = "0.9 0.9" })
hl.window_rule({ match = { class = "^(spotify)$" }, opacity = "0.9 0.9" })
hl.window_rule({ match = { class = "^(Emacs)$" }, opacity = "0.95 0.95" })
hl.window_rule({ match = { class = "^(neovide)$" }, opacity = "0.95 0.95" })
-- WezTerm が native Arch のメインターミナル（Phase 3, #393）。Alacritty ルールは併存期間中のフォールバックとして残す
hl.window_rule({ match = { class = "^(org.wezfurlong.wezterm)$" }, opacity = "0.9 0.9" })
-- NOTE: Alacritty のクラス名は大文字始まり（正規表現は大文字小文字を区別する）
hl.window_rule({ match = { class = "^(Alacritty)$" }, opacity = "0.9 0.9" })

-- 透過を無効にする（完全に不透明にする）
hl.window_rule({ match = { class = "^(Vivaldi-stable)$" }, opaque = true })

-- ─── アニメーション ─────────────────────────────────
hl.window_rule({ match = { class = "^(wofi)$" }, animation = "slide left" })

-- ─── フォーカス制御 ─────────────────────────────────
hl.window_rule({ match = { class = "^(steam_app)$" }, immediate = true })
hl.window_rule({ match = { class = "^(steam_app)$", title = "^(Steam Input Keyboard)$" }, no_focus = true })
hl.window_rule({ match = { class = "^(Vivaldi-stable)$" }, immediate = true })
hl.window_rule({ match = { class = "^(Vivaldi-stable)$", title = "^()$" }, no_focus = true })

-- ─── アプリからの状態変更要求 ───────────────────────
-- アプリが自分で出す最大化要求を無視する。配置を決めるのは Hyprland だけにして、
-- 同じワークスペースの他ウィンドウが覆われるのを防ぐ（#642）。
-- フルスクリーン要求は止めない（ゲームや動画が自分で全画面になるのは正当な動き）。
--   Ignore app-initiated maximize requests so only Hyprland decides window placement and
--   other windows on the same workspace never get covered (#642). Fullscreen requests are
--   intentionally left alone (games/videos going fullscreen on their own is legitimate).
hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })

-- ─── ダイアログとポップアップ ───────────────────────
hl.window_rule({ match = { title = "^(Open File)$" }, float = true })
hl.window_rule({ match = { title = "^(Save File)$" }, float = true })
hl.window_rule({ match = { title = "^(Save As)$" }, float = true })
hl.window_rule({ match = { title = "^(File Upload)$" }, float = true })
hl.window_rule({ match = { title = "^(File Download)$" }, float = true })
hl.window_rule({ match = { title = "^(Confirm to replace files)$" }, float = true })
hl.window_rule({ match = { title = "^(Warning)$" }, float = true })
hl.window_rule({ match = { title = "^(Error)$" }, float = true })

-- ─── ゲーム関連 ─────────────────────────────────────
hl.window_rule({ match = { class = "^(steam_app).*" }, fullscreen = true })
hl.window_rule({ match = { class = "^(steam_app).*" }, workspace = "6 silent" })
hl.window_rule({ match = { class = "^(lutris)$" }, workspace = "6 silent" })

-- ─── その他のアプリケーション ───────────────────────
hl.window_rule({ match = { class = "^(mpv)$" }, float = true })
hl.window_rule({ match = { class = "^(imv)$" }, float = true })
hl.window_rule({ match = { class = "^(nwg-look)$" }, float = true })
hl.window_rule({ match = { class = "^(qt5ct)$" }, float = true })
hl.window_rule({ match = { class = "^(eog)$" }, float = true })
hl.window_rule({ match = { class = "^(Spotify)$" }, tile = true })

-- ─── XWaylandアプリケーション ───────────────────────
hl.window_rule({ match = { xwayland = true }, rounding = 0 })
hl.window_rule({ match = { xwayland = true }, opacity = "0.95 0.95" })

-- XWayland アプリのドラッグ中に出る、クラスもタイトルも空の浮動ウィンドウにフォーカスを渡さない
-- (公式の例 /usr/share/hypr/hyprland.lua の fix-xwayland-drags と同じ条件)
-- Keep focus away from the class-less, title-less floating windows XWayland apps create while dragging
-- (same match as fix-xwayland-drags in the official example /usr/share/hypr/hyprland.lua)
hl.window_rule({
  name  = "fix-xwayland-drags",
  match = {
    class      = "^$",
    title      = "^$",
    xwayland   = true,
    float      = true,
    fullscreen = false,
    pin        = false,
  },
  no_focus = true,
})

-- ─── ピクチャーインピクチャーモード ─────────────────
-- 旧設定の `move = 75% 75%` は、0.57 の式パーサ(muParser)が `%` を解釈しないため
-- モニタ寸法の式 monitor_w*0.75 / monitor_h*0.75 に書き換えた(位置はモニタ内の座標)
-- The former `move = 75% 75%` is rewritten as monitor_w*0.75 / monitor_h*0.75, because the
-- 0.57 expression parser (muParser) does not understand `%` (positions are monitor-local)
hl.window_rule({
  name = "picture-in-picture",
  match = { title = "^(Picture-in-Picture|Picture in picture)$" },
  pin = true,
  float = true,
  size = { 500, 280 },
  move = { "monitor_w*0.75", "monitor_h*0.75" },
})
