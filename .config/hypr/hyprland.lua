-- #######################################################################################
-- Hyprland のメイン設定(エントリ)。Hyprland 0.57 から .conf(hyprlang)形式は読まれないため Lua で書く。
-- 旧 hyprland.conf の内容を 1 対 1 で写し、分割していたファイルは require で読む。
-- Main Hyprland config (entry point). Hyprland 0.57+ no longer reads .conf (hyprlang), so this is Lua.
-- Ported 1:1 from the former hyprland.conf; the split files are loaded with require.
-- API の型定義 / API stubs: /usr/share/hypr/stubs/hl.meta.lua
-- 公式の例 / official example: /usr/share/hypr/hyprland.lua
-- #######################################################################################

-- 設定ファイルのインポート
-- package.path の先頭は設定ディレクトリなので、require("themes.mocha") は themes/mocha.lua を読む。
-- require は読み込んだモジュールをキャッシュするので、同じモジュールを何度 require しても実行は 1 回だけ。
-- plugins.lua はテーマを自分で require し、keybinds.lua からも require される(下の順序は旧 source の順を写したもの)。
-- Import the split config files.
-- package.path starts with the config directory, so require("themes.mocha") loads themes/mocha.lua.
-- require caches modules, so each one runs only once however many times it is required.
-- plugins.lua requires the theme itself and is also required by keybinds.lua (the order below mirrors the former source lines).
require("startup")
require("keybinds")
require("window_rules")
require("themes.mocha")
require("plugins")


------------------
---- MONITORS ----
------------------

-- モニターの配置と、フタに合わせた内蔵画面の有効・無効は monitors.lua に分けた(#836)
-- Monitor layout and the lid-driven internal panel handling live in monitors.lua (#836)
require("monitors")


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/configuring/core/environment-variables/

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")


-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Refer to https://wiki.hypr.land/configuring/core/config-options/

-- 外観の設定 / appearance
hl.config({
  general = {
    gaps_in  = 5,
    gaps_out = 20,

    border_size = 2,

    -- グラデーションは { colors = {...}, angle = 度 } で書く / gradients are { colors = {...}, angle = degrees }
    col = {
      active_border   = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
      inactive_border = "rgba(595959aa)",
    },

    -- 枠と隙間をドラッグしてウィンドウの大きさを変えられるようにする / resize windows by dragging their borders and gaps
    resize_on_border = true,

    -- 有効にする前に wiki を読む / read this before enabling: https://wiki.hypr.land/configuring/extra/tearing/
    allow_tearing = false,

    layout = "dwindle",
  },

  decoration = {
    rounding = 10,

    -- フォーカスの有無ごとの不透明度 / opacity of focused and unfocused windows
    active_opacity   = 1.0,
    inactive_opacity = 1.0,

    shadow = {
      enabled      = true,
      range        = 4,
      render_power = 3,
      color        = "rgba(1a1a1aee)",
    },

    blur = {
      enabled  = true,
      size     = 3,
      passes   = 1,
      vibrancy = 0.1696,
    },
  },

  -- アニメーション設定 / animations
  animations = {
    enabled = true,
  },
})

-- アニメーション / animations: https://wiki.hypr.land/configuring/core/animations/
-- 旧 animations ブロック内の bezier / animation は、0.57 では hl.curve / hl.animation のトップレベル呼び出しになる
-- The bezier / animation lines of the former animations block are top-level hl.curve / hl.animation calls in 0.57
hl.curve("myBezier", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })

hl.animation({ leaf = "windows",     enabled = true, speed = 7,  bezier = "myBezier" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 7,  bezier = "default", style = "popin 80%" })
hl.animation({ leaf = "border",      enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 8,  bezier = "default" })
hl.animation({ leaf = "fade",        enabled = true, speed = 7,  bezier = "default" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 6,  bezier = "default" })

hl.config({
  -- See https://wiki.hypr.land/configuring/layouts/dwindle-layout/ for more
  dwindle = {
    -- NOTE: v0.55 で dwindle:pseudotile オプションは廃止。擬似タイル化は keybinds.lua の `pseudo` dispatcher (mainMod+P) で操作する
    -- NOTE: dwindle:pseudotile option removed in v0.55; use the `pseudo` dispatcher instead
    -- ウィンドウを閉じても分割の向きを保つ / keep the split direction when windows close
    preserve_split = true,
  },

  -- See https://wiki.hypr.land/configuring/layouts/master-layout/ for more
  master = {
    new_status = "master",
  },

  misc = {
    -- obsidian:// URI 経由の Web Clipper 連携のため、アクティベーション要求時にフォーカスを渡す
    -- (Wayland では非フォーカスウィンドウはクリップボードを読めず、クリップ本文が空になる)
    -- NOTE: allow apps to take focus on activation; required for Obsidian Web Clipper
    --       (unfocused windows cannot read the clipboard on Wayland → empty clip body)
    focus_on_activate = true,
    -- NOTE: v0.55 で misc:vfr は debug: 配下に移動（本番設定では触らない。VFR はデフォルトで有効）
    -- NOTE: misc:vfr moved to debug: in v0.55; VFR is on by default and should not be set in prod
  },

  binds = {
    -- 同じワークスペース番号を再押下すると直前のワークスペースに戻る(Windows の Win+数字 再押下トグルと同等の挙動)
    -- keybinds.lua の `hl.bind(mainMod .. " + Tab", hl.dsp.focus({ workspace = "previous" }))` とは独立して併用可能
    -- NOTE: pressing the same workspace number again toggles back to the previous workspace (like Windows' Win+number re-press toggle)
    -- NOTE: works alongside the `mainMod + Tab` -> `focus({ workspace = "previous" })` bind in keybinds.lua
    workspace_back_and_forth = true,
  },
})


---------------
---- INPUT ----
---------------

-- 入力デバイスの設定 / input devices
hl.config({
  input = {
    kb_layout  = "us",
    kb_variant = "",
    kb_model   = "",
    kb_options = "ctrl:nocaps", -- CapsLockをCtrlに / CapsLock as Ctrl
    kb_rules   = "",

    follow_mouse = 1,

    sensitivity = 0, -- -1.0〜1.0、0 は変更なし / -1.0 to 1.0, 0 means no modification

    -- タッチパッドを MacBook に近い操作にする(#836)。タッチパッドの無い機械では何も起こさない。
    -- この節はタッチパッドだけに効き、マウスのスクロールの向きは変えない。
    -- Make the touchpad behave like a MacBook's (#836); a no-op on machines without one.
    -- This section applies to touchpads only, so the mouse keeps its scroll direction.
    touchpad = {
      -- 指を動かした向きに中身が動く(ナチュラルスクロール) / content follows the fingers
      natural_scroll = true,
      -- 押し込んだ指の本数でボタンを決める: 1 本 = 左、2 本 = 右、3 本 = 中。パッドの右下を押す方式は無効になる
      -- Buttons by finger count: 1 = left, 2 = right, 3 = middle; disables the bottom-right click area
      clickfinger_behavior = true,
      -- 次の 3 つは初期値と同じだが、MacBook 化の前提なので明示する
      -- The next three equal the defaults; spelled out because the MacBook-like setup relies on them
      tap_to_click         = true, -- タップでクリック(2 本指タップ = 右クリック) / tap to click (two-finger tap = right click)
      tap_and_drag         = true, -- タップしてすぐ押さえたまま動かすとドラッグ / tap, then hold and move to drag
      disable_while_typing = true, -- 入力中の誤タッチを無視する / ignore accidental touches while typing
    },
  },
})


------------------
---- GESTURES ----
------------------

-- 3 本指の左右スワイプでワークスペースを切り替える(MacBook の「フルスクリーンアプリケーション間をスワイプ」に当たる)。
-- 対象はカーソルのあるモニターのワークスペースで、指の動きに 1:1 で追従する。
-- 3 本指の上下スワイプ(俯瞰の開閉)は hyprtasking が自前で処理するので、plugins.lua の gestures で設定している。
-- Three-finger horizontal swipe switches workspaces (macOS "swipe between full-screen apps").
-- It acts on the monitor under the cursor and follows the fingers 1:1.
-- Three-finger vertical swipe (open/close the overview) is handled by hyprtasking itself; see gestures in plugins.lua.
-- See https://wiki.hypr.land/configuring/core/binds/gestures/
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
