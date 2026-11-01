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

-- See https://wiki.hypr.land/configuring/core/monitors/
hl.monitor({
  output   = "",
  mode     = "preferred",
  position = "auto",
  scale    = "auto",
})


---------------------
---- MY PROGRAMS ----
---------------------

-- Set programs that you use
-- 旧設定と同じく定義だけで、keybinds.lua では使っていない / defined only, as before; keybinds.lua does not use them
local terminal    = "Alacritty"
local fileManager = "dolphin"
local menu        = "wofi --show drun"


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

    -- Set to true enable resizing windows by clicking and dragging on borders and gaps
    resize_on_border = true,

    -- Please see https://wiki.hypr.land/configuring/extra/tearing/ before you turn this on
    allow_tearing = false,

    layout = "dwindle",

    -- cursor_inactive_timeout = 5
  },

  decoration = {
    rounding = 10,

    -- Change transparency of focused and unfocused windows
    active_opacity   = 1.0,
    inactive_opacity = 1.0,

    shadow = {
      enabled      = true,
      range        = 4,
      render_power = 3,
      color        = "rgba(1a1a1aee)",
    },

    -- https://wiki.hypr.land/configuring/core/config-options/
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

-- Default animations, see https://wiki.hypr.land/configuring/core/animations/ for more
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
    preserve_split = true, -- You probably want this
  },

  -- See https://wiki.hypr.land/configuring/layouts/master-layout/ for more
  master = {
    new_status = "master",
  },

  misc = {
    force_default_wallpaper = -1, -- Set to 0 or 1 to disable the anime mascot wallpapers
    disable_hyprland_logo = false, -- If true disables the random hyprland logo / anime girl background. :(
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

    sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

    touchpad = {
      natural_scroll = false,
    },
  },

  gestures = {
    workspace_swipe_forever = true,
  },
})

-- Example per-device config
-- See https://wiki.hypr.land/configuring/core/devices/ for more
hl.device({
  name        = "epic-mouse-v1",
  sensitivity = -0.5,
})
