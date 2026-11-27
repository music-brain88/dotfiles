------------------
---- MONITORS ----
------------------
-- モニターの配置、ワークスペースの割り当て、ノート PC のフタに合わせた内蔵画面の有効・無効(#836)。
-- Monitor layout, workspace assignment, and enabling/disabling the laptop's internal panel with its lid (#836).
-- See https://wiki.hypr.land/configuring/core/monitors/

-- 既定のルール: 下に個別のルールが無い出力は、推奨の解像度で自動配置する。
-- Default rule: outputs without a rule of their own below use the preferred mode and automatic placement.
local DEFAULT_RULE = {
  mode     = "preferred",
  position = "auto",
  scale    = "auto",
}

hl.monitor({
  output   = "",
  mode     = DEFAULT_RULE.mode,
  position = DEFAULT_RULE.position,
  scale    = DEFAULT_RULE.scale,
})

-- 机の上の並びに合わせた配置。外部モニター 2 枚を横に並べ、ノート PC の内蔵画面をその境目の真下に置く。
-- Layout matching the desk: two external monitors side by side, the laptop's panel right below their seam.
--
--   ┌──────────┐┌──────────────┐
--   │ BenQ 24" ││   Dell 27"   │   BenQ 1920x1080 / Dell 2560x1440
--   └──────────┘└──────────────┘
--          ┌──────────┐
--          │ internal │              1920x1200, scale 1.5 -> 1280x800
--          └──────────┘
--
-- 出力はポート名(DP-3 など)ではなく機種名の前方一致(desc:)で指定する。挿すポートが変わっても崩れず、
-- この機種をつないでいない機械では、どのルールも一致しないので何も起きない。
-- position は scale を掛けた後の論理ピクセルで書く。外部モニターは下端をそろえる(y = 1440)。
-- 内蔵画面は幅 1280 なので、境目(x = 1920)の真下に置くには x = 1920 - 640 = 1280 にする。
-- Outputs are matched by a description prefix (desc:), not by port name (DP-3 etc.): the layout survives a port
-- change, and on machines without these models no rule matches, so nothing happens.
-- position is in logical pixels after scale. The externals are bottom-aligned (y = 1440).
-- The panel is 1280 wide, so centering it under the seam (x = 1920) gives x = 1920 - 640 = 1280.
local BENQ     = "desc:BNQ BenQ GW2470"
local DELL     = "desc:Dell Inc. DELL P2723DE"
local INTERNAL = "desc:China Star Optoelectronics Technology Co. Ltd 0x146B"

local MONITOR_RULES = {
  { output = BENQ,     mode = "preferred", position = "0x360",     scale = 1 },
  { output = DELL,     mode = "preferred", position = "1920x0",    scale = 1 },
  { output = INTERNAL, mode = "preferred", position = "1280x1440", scale = 1.5 },
}

for _, rule in ipairs(MONITOR_RULES) do
  hl.monitor(rule)
end


------------------------------------------------
---- ワークスペースの割り当て / workspaces ----
------------------------------------------------
-- 作業台(ws1〜3)をメインの Dell に、詰め所(ws4〜6)を BenQ に、予備(ws7〜9)を内蔵画面に置く。
-- 各モニターの先頭(1 / 4 / 7)を、そのモニターが最初に表示するワークスペースにする。
-- 割り当て先のモニターをつないでいない機械では、そのモニター向けのルールは一致する出力が無い。
-- The workbench (ws1-3) goes on the main Dell, the depot (ws4-6) on the BenQ, spares (ws7-9) on the panel.
-- The first of each range (1 / 4 / 7) is the workspace that monitor shows first.
-- On machines without the target monitor, the rules for that monitor have no output to match.
-- See https://wiki.hypr.land/configuring/core/rules/workspace-rules/
local WORKSPACE_MONITORS = {
  { monitor = DELL,     first = 1 },
  { monitor = BENQ,     first = 4 },
  { monitor = INTERNAL, first = 7 },
}

for _, group in ipairs(WORKSPACE_MONITORS) do
  for id = group.first, group.first + 2 do
    hl.workspace_rule({
      workspace = tostring(id),
      monitor   = group.monitor,
      default   = id == group.first,
    })
  end
end


-------------------------------------
---- フタと内蔵画面 / lid & panel ----
-------------------------------------
-- 外部モニターをつないだままフタを閉じたら、内蔵画面を無効にする(クラムシェル運用)。
-- 無効にした画面のウィンドウとワークスペースは、Hyprland が残りのモニターへ移す。
-- 外部モニターが無いときは無効にしない(そのときフタを閉じると、systemd-logind の初期設定でサスペンドする)。
-- フタのスイッチも内蔵画面も無い機械(デスクトップ)では、下の処理は何もしない。
-- Closing the lid while an external monitor is connected disables the internal panel (clamshell mode).
-- Hyprland moves the windows and workspaces of a disabled monitor to the remaining ones.
-- With no external monitor the panel stays enabled (closing the lid then suspends, per systemd-logind's defaults).
-- On machines with neither a lid switch nor an internal panel (desktops) none of this does anything.

-- 内蔵画面の出力名は eDP で始まる / the internal panel's output name starts with eDP
local INTERNAL_PATTERN = "^eDP"

-- 内蔵画面に当てるルールを返す。内蔵画面が無ければ nil。無効にした出力も探すので all = true を付ける。
-- 上の MONITOR_RULES に機種が一致するルールがあればその写しを返し、無ければ出力名に既定のルールを当てる。
-- 同じ output の文字列で上書きするので、フタを開けたときに配置と scale が上の指定どおりに戻る。
-- Returns the rule to apply to the internal panel, or nil without one; all = true also lists disabled outputs.
-- A copy of the matching MONITOR_RULES entry if the model is known, else the default rule under the output name.
-- Reusing the same output string means opening the lid restores the position and scale given above.
local function internal_rule()
  for _, monitor in ipairs(hl.get_monitors({ all = true })) do
    if monitor.name:match(INTERNAL_PATTERN) then
      for _, rule in ipairs(MONITOR_RULES) do
        local prefix = rule.output:gsub("^desc:", "")
        if monitor.description:sub(1, #prefix) == prefix then
          return { output = rule.output, mode = rule.mode, position = rule.position, scale = rule.scale }
        end
      end
      return {
        output   = monitor.name,
        mode     = DEFAULT_RULE.mode,
        position = DEFAULT_RULE.position,
        scale    = DEFAULT_RULE.scale,
      }
    end
  end
  return nil
end

-- 有効な外部モニターが 1 枚でもあるか。removed には、いま抜かれたモニターの名前を渡す。
-- monitor.removed のイベントが届いた時点で、抜かれたモニターがまだ一覧に残っていても数えないようにするため。
-- Whether at least one external monitor is enabled. removed is the name of a monitor being unplugged,
-- so that it is not counted even if it is still listed when the monitor.removed event arrives.
local function has_external_monitor(removed)
  for _, monitor in ipairs(hl.get_monitors()) do
    if not monitor.name:match(INTERNAL_PATTERN) and monitor.name ~= removed then
      return true
    end
  end
  return false
end

-- フタが閉じているかをカーネルの ACPI の状態から読む。ファイルが無い機械では false。
-- 設定の読み直しとモニターの抜き差しのときは、スイッチのイベントが来ないので、ここから現在の状態を得る。
-- Reads whether the lid is closed from the kernel's ACPI state; false on machines without the file.
-- Config reloads and monitor hotplug bring no switch event, so the current state comes from here.
local function lid_is_closed()
  for _, name in ipairs({ "LID0", "LID", "LID1" }) do
    local file = io.open("/proc/acpi/button/lid/" .. name .. "/state")
    if file then
      local state = file:read("a")
      file:close()
      return state:find("closed", 1, true) ~= nil
    end
  end
  return false
end

-- 内蔵画面の有効・無効を、フタの状態と外部モニターの有無に合わせる。
-- closed を省くと、フタの状態を ACPI から読む。removed は has_external_monitor にそのまま渡す。
-- Syncs the internal panel with the lid state and the presence of an external monitor.
-- When closed is omitted the lid state is read from ACPI; removed is passed on to has_external_monitor.
local function sync_internal_panel(closed, removed)
  local rule = internal_rule()
  if rule == nil then
    return
  end
  if closed == nil then
    closed = lid_is_closed()
  end
  rule.disabled = closed and has_external_monitor(removed)
  hl.monitor(rule)
end

-- フタの開閉。ロック画面の表示中も働くように locked を付ける。スイッチ名は `hyprctl devices` の Switches で確かめられる。
-- Lid close / open; locked keeps them working on the lock screen. `hyprctl devices` lists the switch name under Switches.
hl.bind("switch:on:Lid Switch", function () sync_internal_panel(true) end, { locked = true })
hl.bind("switch:off:Lid Switch", function () sync_internal_panel(false) end, { locked = true })

-- フタを閉じたまま外部モニターを抜いたら内蔵画面を戻し、閉じたままつないだら無効にする。
-- Unplugging the last external monitor with the lid closed re-enables the panel; plugging one in disables it.
hl.on("monitor.added", function () sync_internal_panel() end)
hl.on("monitor.removed", function (monitor) sync_internal_panel(nil, monitor and monitor.name) end)

-- 設定を読み直すと上の既定のルールで内蔵画面が有効に戻るので、フタが閉じていればここで無効にし直す。
-- A config reload re-enables the panel through the default rule above, so disable it again here if the lid is closed.
if lid_is_closed() then
  sync_internal_panel(true)
end
