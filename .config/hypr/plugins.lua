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
        -- 俯瞰の形。"linear" は、画面の端にワークスペースの帯(ミニマップ)を出し、今の画面は見えたまま残す。
        -- "grid" は、画面全体をワークスペースのタイルで埋める。切り替わるのは設定を読み直したときだけで、
        -- 実行中にキーで行き来はできない。俯瞰を多用するので、今の作業を隠さない帯のほうを使う(#836)。
        -- 帯には、そのモニターにいま存在するワークスペースが番号順に並び、末尾に新しい空きが 1 つ付く。
        -- Overview shape. "linear" shows a strip of workspaces (a minimap) along a screen edge and keeps the
        -- current screen visible; "grid" fills the screen with workspace tiles. It only changes on a config
        -- reload, not from a key at runtime. The overview is used a lot, so the strip, which does not hide the
        -- work in progress, is the one in use (#836). The strip lists the monitor's existing workspaces in
        -- numeric order, plus one new empty one at the end.
        layout = "linear",

        linear = {
          -- 帯を画面の上端に出す(macOS の Mission Control と同じ位置) / strip at the top, like Mission Control
          top    = true,
          -- 帯の高さ(論理ピクセル)。内蔵画面は論理 800px しか無いので、初期値の 300 より低くする
          -- Strip height in logical px; the laptop panel is only 800 logical px tall, hence less than the default 300
          height = 240,
          -- 帯の外(今の画面)をぼかさない。ミニマップとして、作業中の画面を読めるまま残す
          -- Do not blur the area outside the strip, so the screen in use stays readable under the minimap
          blur   = false,
        },

        -- 下の grid は layout = "grid" のときだけ使われる。戻すときのために残してある。
        -- The grid block below only applies with layout = "grid"; kept for switching back.

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
        -- MacBook は 3 本指の上スワイプが Mission Control なので、開閉を 3 本指にする。
        -- 3 本指の左右スワイプは hyprtasking が処理しないので、hyprland.lua の hl.gesture(ワークスペース切り替え)に渡る。
        -- グリッド上の移動(move_fingers)は layout = "grid" のときだけ働き、帯のレイアウトでは何も起こさない。
        -- それでも hyprtasking はその本数のスワイプを受け取ってしまうので、使っていない 5 本指に逃がしてある
        -- (このタッチパッドは 4 本指までしか数えられないので、5 本指は実際には来ない)。空いた 4 本指は、
        -- hyprland.lua の hl.gesture(全モニターの俯瞰の開閉)が使う。開閉と移動を同じ本数にはしない。
        -- Match the touchpad gestures to a MacBook's (#836).
        -- hyprtasking defaults to "3 fingers = move across the grid, 4 fingers up/down = open/close the overview".
        -- macOS opens Mission Control with a three-finger swipe up, so open/close goes on 3.
        -- hyprtasking ignores three-finger horizontal swipes, so they reach hl.gesture (workspace switch) in hyprland.lua.
        -- The grid move (move_fingers) only works with layout = "grid" and does nothing with the strip layout,
        -- yet hyprtasking still swallows swipes of that finger count, so it is parked on the unused five
        -- (this touchpad tracks at most four fingers, so five never arrive). The freed four fingers are used by
        -- hl.gesture in hyprland.lua (open/close the overview on all monitors). Never give both the same count.
        gestures = {
          enabled       = true,
          open_fingers  = 3,
          move_fingers  = 5,
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
