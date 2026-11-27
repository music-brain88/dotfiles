------------------------
---- PLUGINS (#549) ----
------------------------
-- hyprtasking: ワークスペース俯瞰(overview)。hyprexpo が upstream で unmaintained
-- として削除されたため、後継としてこちらを採用。プラグイン本体は hyprpm 管理
-- (dotfiles 管理外)で、Hyprland 更新のたびに `hyprpm update` で要再ビルド(ABI 完全一致必須)。
-- hyprtasking: workspace overview. Adopted as the successor to hyprexpo, which was
-- dropped upstream as unmaintained. The plugin binary is managed by hyprpm (outside
-- dotfiles); rebuild with `hyprpm update` after every Hyprland upgrade (exact ABI match).
--
-- 前提: hyprpm は hyprland とは別の pacman パッケージ(extra/hyprpm)。事前に `sudo pacman -S hyprpm` で導入しておくこと。
-- Prerequisite: hyprpm is a separate pacman package (extra/hyprpm) from hyprland; install it first with `sudo pacman -S hyprpm`.
--
-- 操作: SUPER+grave でトグル(keybinds.lua)、右クリックでそのWSに入る、左ドラッグで窓を別WSへ引っ越し
-- Usage: SUPER+grave toggles (keybinds.lua); right-click enters a workspace, left-drag moves windows.
-- 全オプション / all options: https://github.com/raybbian/hyprtasking#config-options

local c = require("themes.mocha")

local M = {}

-- プラグインの読み込み判定をここに 1 つだけ置く。設定ブロックと bind の両方がこの関数を使う。
-- hyprpm reload -n は hyprland.start で走るので、起動直後の最初の読み込みでは必ず nil になる。
-- プラグインが読み込まれると Hyprland は設定を読み直し、そのときは hl.plugin.<name> が存在する。
-- The single place that decides whether a plugin is loaded; both the config block and the binds use it.
-- `hyprpm reload -n` runs on hyprland.start, so this is always nil on the very first config load.
-- Hyprland reloads the config after a plugin loads, and hl.plugin.<name> exists on that reload.
function M.loaded(name)
  return hl.plugin[name]
end

-- プラグインの関数を呼ぶ bind 用のクロージャを返す。キーを押した時点で読み込みを判定し、
-- 未読み込みなら Hyprland の通知を出して何もしない。
-- Returns a closure for a bind that calls into a plugin. It checks at key-press time and,
-- if the plugin is not loaded, shows a Hyprland notification and does nothing.
function M.action(name, fn)
  return function ()
    local plugin = M.loaded(name)
    if plugin == nil then
      hl.notification.create({
        text = name .. " が読み込まれていません(mise run hypr:pm-update でビルドする) / " .. name .. " is not loaded",
        timeout = 5000,
        icon = "warning",
      })
      return
    end
    fn(plugin)
  end
end

-- hyprtasking の bg_color は整数型(0xAARRGGBB)なので、テーマの "rgb(RRGGBB)" を不透明の整数に変換する
-- hyprtasking's bg_color is an integer (0xAARRGGBB), so convert the theme's "rgb(RRGGBB)" to an opaque integer
local function rgb_to_argb(color)
  local hex = color:match("^rgb%((%x%x%x%x%x%x)%)$")
  assert(hex, "rgb_to_argb: expected rgb(RRGGBB), got " .. tostring(color))
  return 0xFF000000 | tonumber(hex, 16)
end

-- プラグインが無いときは設定ブロックを黙ってスキップする(読み込みの失敗は hyprpm reload -n が自分で通知する)
-- Silently skip the block when the plugin is absent (hyprpm reload -n reports load failures itself)
if M.loaded("hyprtasking") ~= nil then
  hl.config({
    plugin = {
      hyprtasking = {
        layout = "grid",

        -- 2列x3行の6面グリッド: 作業台 ws1-3 + 詰め所 ws4-6 の主戦場がちょうど収まる
        -- 2x3 grid fits the six daily workspaces (workbench ws1-3 + depot ws4-6)
        grid = {
          rows = 3,
          cols = 2,
        },

        bg_color = rgb_to_argb(c.crust),
        gap_size = 10,
        border_size = 6,

        -- タッチパッドのジェスチャーを MacBook の割り当てに合わせる(#836)。
        -- hyprtasking の初期値は「3 本指 = グリッド上の移動、4 本指の上下 = 俯瞰の開閉」。
        -- MacBook は 3 本指の上スワイプが Mission Control なので、開閉を 3 本指に、グリッド上の移動を 4 本指に入れ替える。
        -- 開閉と移動を同じ本数にすると開閉だけが働く(プラグインは開閉の本数を先に判定する)ので、必ず別の本数にする。
        -- 3 本指の左右スワイプは hyprtasking が処理しないので、hyprland.lua の hl.gesture(ワークスペース切り替え)に渡る。
        -- Match the touchpad gestures to a MacBook's (#836).
        -- hyprtasking defaults to "3 fingers = move across the grid, 4 fingers up/down = open/close the overview".
        -- macOS opens Mission Control with a three-finger swipe up, so swap them: open/close on 3, grid move on 4.
        -- The two must differ: with the same count only open/close works (the plugin checks open_fingers first).
        -- hyprtasking ignores three-finger horizontal swipes, so they reach hl.gesture (workspace switch) in hyprland.lua.
        gestures = {
          enabled       = true,
          open_fingers  = 3,
          move_fingers  = 4,
          -- true: 上スワイプで開き、下スワイプで閉じる / true: swipe up opens, swipe down closes
          open_positive = true,
        },

        jump = {
          -- 俯瞰中にラベルキーで一発でワープできる
          -- jump to a workspace with a single label key while in the overview
          enabled = true,
        },
      },
    },
  })
end

-- 俯瞰のグリッドの大きさを変える。モニターの構成に合わせて monitors.lua から呼ぶ(#836)。
-- hyprtasking は、そのモニターに割り当てたワークスペースを先にマスへ並べ、余ったマスには
-- 割り当ての無い番号(ws10 以降)を作って埋める。マスの数を担当の数に合わせると、俯瞰に余計な番号が出ない。
-- プラグインが無いときは何もしない。
-- Resizes the overview grid; called from monitors.lua to match the monitor setup (#836).
-- hyprtasking fills the slots with the monitor's assigned workspaces first and invents unassigned numbers
-- (ws10 and up) for the rest, so matching the slot count to the assigned count keeps stray numbers out.
-- Does nothing when the plugin is absent.
function M.set_overview_grid(rows, cols)
  if M.loaded("hyprtasking") == nil then
    return
  end
  hl.config({
    plugin = {
      hyprtasking = {
        grid = {
          rows = rows,
          cols = cols,
        },
      },
    },
  })
end

return M
