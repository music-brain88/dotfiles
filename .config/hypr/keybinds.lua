----------------------
---- キーバインド ----
----------------------
-- 旧 keybinds.conf の bind / binde / bindl / bindel / bindm を 1 行ずつ hl.bind に写したもの。
-- binde は { repeating = true }、bindl は { locked = true }、bindel は両方、bindm は { mouse = true } に対応する。
-- Each bind / binde / bindl / bindel / bindm line of the former keybinds.conf maps to one hl.bind call.
-- binde -> { repeating = true }, bindl -> { locked = true }, bindel -> both, bindm -> { mouse = true }.

local plugins = require("plugins")

-- メインのモディファイヤーキーをSuperキー（Windowsキー）に設定
-- Main modifier is the Super (Windows) key
local mainMod = "SUPER"

---- システム管理 ----
-- パッケージ管理
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("wezterm start -- paru"))
-- 通知制御
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("~/.config/hypr/scripts/notifications.sh toggle"))
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.exec_cmd("~/.config/hypr/scripts/notifications.sh clear"))
-- クリップボード履歴（cliphist の履歴を wofi で選んでコピー）
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd("cliphist list | wofi --dmenu | cliphist decode | wl-copy"))
-- システムモニタリング
-- hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("alacritty -e btm"))

---- アプリケーションの起動 ----
-- ターミナル（WezTerm）
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd("wezterm"))
-- ブラウザ（Vivaldi）
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("vivaldi-stable"))
-- ファイルマネージャー（Nautilus）
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("nautilus"))
-- アプリケーションランチャー（Wofi）
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("wofi --show drun"))
hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd("wofi --show drun"))
-- スクリーンロック（Hyprlock）
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"))
-- ログアウトメニュー（Wlogout）
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("wlogout"))

---- ウィンドウ管理 ----
-- アクティブウィンドウを終了(旧 killactive。graceful close で、SIGKILL の kill とは別物)
-- Close the active window (former killactive; a graceful close, not the SIGKILL `kill`)
hl.bind("ALT + F4", hl.dsp.window.close())
-- Hyprlandを終了
-- hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exit())
-- フローティングモードの切り替え
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
-- 疑似タイリングモードの切り替え
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
-- タイリングの分割方向を切り替え
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

--- ウィンドウの最大化(旧 `fullscreen, 0` = 全画面)
--- Fullscreen (former `fullscreen, 0`)
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))


-- リサイズモードのサブマップを定義
-- Enter the resize submap
hl.bind(mainMod .. " + R", hl.dsp.submap("resize"))

-- リサイズモードのキーバインド(define_submap の関数内の bind だけがこのサブマップに属する)
-- Resize-mode binds (only binds inside the define_submap function belong to this submap)
hl.define_submap("resize", function ()
  -- 矢印キー
  hl.bind("left", hl.dsp.window.resize({ x = -10, y = 0, relative = true }), { repeating = true })
  hl.bind("down", hl.dsp.window.resize({ x = 0, y = 10, relative = true }), { repeating = true })
  hl.bind("up", hl.dsp.window.resize({ x = 0, y = -10, relative = true }), { repeating = true })
  hl.bind("right", hl.dsp.window.resize({ x = 10, y = 0, relative = true }), { repeating = true })

  -- デフォルトモードに戻る
  hl.bind("Return", hl.dsp.submap("reset"))
  hl.bind("Escape", hl.dsp.submap("reset"))
  hl.bind(mainMod .. " + R", hl.dsp.submap("reset"))
end)
-- ここから下はグローバルのサブマップに戻る / binds below are global again

---- ウィンドウ管理 ----

-- windowの切り替え（Hyprland組み込みのcyclenextで現在のワークスペース内のみを対象にする / built-in cyclenext, scoped to the current workspace only）
--- ワークスペース内のウィンドウ切り替え（同一キーへの複数bindは順に実行される / stacked binds on the same key run in sequence）
hl.bind("ALT + Tab", hl.dsp.window.cycle_next())
hl.bind("ALT + Tab", hl.dsp.window.alter_zorder({ mode = "top" }))
--- ワークスペース内のウィンドウ切り替え（逆順） / same, in reverse order
hl.bind("ALT + SHIFT + Tab", hl.dsp.window.cycle_next({ next = false }))
hl.bind("ALT + SHIFT + Tab", hl.dsp.window.alter_zorder({ mode = "top" }))

---- フォーカス移動 ----
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

---- ウィンドウの移動 ----
hl.bind(mainMod .. " + SHIFT + left", hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + up", hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + down", hl.dsp.window.move({ direction = "down" }))

---- マウス操作 ----
-- Super+左ドラッグでウィンドウ移動、Super+右ドラッグでリサイズ
-- Super + left drag moves a window, Super + right drag resizes it
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

---- ワークスペース操作 ----
-- hyprtasking overview のトグル (#549)。README 推奨の SUPER+Tab / SUPER+Space は
-- 直前WS戻り / wofi で使用済みのため grave(バッククォート)を採用。
-- プラグインが未読み込みのときは押した時点で通知だけ出す(判定は plugins.lua の 1 関数に集約)
-- Toggle the hyprtasking overview (#549); Tab/Space suggested upstream are already taken.
-- If the plugin is not loaded, pressing the key only shows a notification (the check lives in plugins.lua)
hl.bind(mainMod .. " + grave", plugins.action("hyprtasking", function (ht) ht.toggle("cursor") end))

-- ワークスペースへの移動
hl.bind(mainMod .. " + 1", hl.dsp.focus({ workspace = 1 }))
hl.bind(mainMod .. " + 2", hl.dsp.focus({ workspace = 2 }))
hl.bind(mainMod .. " + 3", hl.dsp.focus({ workspace = 3 }))
hl.bind(mainMod .. " + 4", hl.dsp.focus({ workspace = 4 }))
hl.bind(mainMod .. " + 5", hl.dsp.focus({ workspace = 5 }))
hl.bind(mainMod .. " + 6", hl.dsp.focus({ workspace = 6 }))
hl.bind(mainMod .. " + 7", hl.dsp.focus({ workspace = 7 }))
hl.bind(mainMod .. " + 8", hl.dsp.focus({ workspace = 8 }))
hl.bind(mainMod .. " + 9", hl.dsp.focus({ workspace = 9 }))
hl.bind(mainMod .. " + 0", hl.dsp.focus({ workspace = 10 }))

-- ウィンドウをワークスペースに移動(旧 movetoworkspace。follow を省くと移動先へフォーカスも移る)
-- Move the window to a workspace (former movetoworkspace; omitting `follow` also moves focus there)
hl.bind(mainMod .. " + SHIFT + 1", hl.dsp.window.move({ workspace = 1 }))
hl.bind(mainMod .. " + SHIFT + 2", hl.dsp.window.move({ workspace = 2 }))
hl.bind(mainMod .. " + SHIFT + 3", hl.dsp.window.move({ workspace = 3 }))
hl.bind(mainMod .. " + SHIFT + 4", hl.dsp.window.move({ workspace = 4 }))
hl.bind(mainMod .. " + SHIFT + 5", hl.dsp.window.move({ workspace = 5 }))
hl.bind(mainMod .. " + SHIFT + 6", hl.dsp.window.move({ workspace = 6 }))
hl.bind(mainMod .. " + SHIFT + 7", hl.dsp.window.move({ workspace = 7 }))
hl.bind(mainMod .. " + SHIFT + 8", hl.dsp.window.move({ workspace = 8 }))
hl.bind(mainMod .. " + SHIFT + 9", hl.dsp.window.move({ workspace = 9 }))
hl.bind(mainMod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))

-- 直前のワークスペースとトグル（1⇔3 の往復がワンキーに）
-- Toggle back to the previous workspace (1 <-> 3 in one key)
hl.bind(mainMod .. " + Tab", hl.dsp.focus({ workspace = "previous" }))

-- Special Workspace（スクラッチパッド）
-- どのワークスペースからでも呼び出せる隠しポケット / overlay workspace toggle
-- toggle_special は名前だけを取り、special: の接頭辞を付けない(wiki の Dispatchers 参照)
-- toggle_special takes the bare name without the special: prefix (see the wiki's Dispatchers page)
hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + ALT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- 引き出し（参照アプリの named special workspace）
-- どのワークスペースからでも同じキーで呼び出せる「ちょい見」専用オーバーレイ
-- / Drawer: named special workspaces for reference apps, toggled with the same key from any workspace (glance-only)
hl.bind(mainMod .. " + O", hl.dsp.workspace.toggle_special("obsidian"))
hl.bind(mainMod .. " + A", hl.dsp.workspace.toggle_special("claude"))

-- 送り返し: アクティブウィンドウを引き出しへ戻す（#346）。旧 movetoworkspacesilent は follow = false に当たる
-- Send-back: push the active window back into its drawer (#346); former movetoworkspacesilent = follow = false
hl.bind(mainMod .. " + SHIFT + O", hl.dsp.window.move({ workspace = "special:obsidian", follow = false }))
hl.bind(mainMod .. " + SHIFT + A", hl.dsp.window.move({ workspace = "special:claude", follow = false }))

-- Bring / Go 型ウィンドウピッカー（#346）
-- wofi で任意のウィンドウを選び、現在のワークスペースへ引き込む(Bring)か
-- そのウィンドウの場所へ飛ぶ(Go)かを選べる
-- / Bring & Go style window picker: choose any window via wofi, then either
-- pull it into the current workspace (Bring) or jump to where it lives (Go)
hl.bind(mainMod .. " + Y", hl.dsp.exec_cmd("~/.config/hypr/scripts/bring_window.sh bring"))
hl.bind(mainMod .. " + SHIFT + Y", hl.dsp.exec_cmd("~/.config/hypr/scripts/bring_window.sh go"))

---- システム操作 ----
-- コマンドに " と ' が混ざるものは Lua の長括弧文字列 [[...]] で書き、エスケープを避ける
-- Commands mixing " and ' use Lua long-bracket strings [[...]] to avoid escaping
-- スクリーンショット（選択領域をクリップボードにコピー）
hl.bind("Print", hl.dsp.exec_cmd([[grim -g "$(slurp)" - | wl-copy]]))
-- hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd([[grim -g "$(slurp)" - | wl-copy]]))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd([[mkdir -p ~/Pictures/Screenshots && notify-send "ディレクトリ作成" "Screenshots ディレクトリを確認" && grim -g "$(slurp)" ~/Pictures/Screenshots/$(date +'%Y%m%d_%H%M%S').png && notify-send "Screenshot" "保存完了"]]))
-- スクリーンショット（選択領域を画像として保存）
-- hl.bind("SHIFT + Print", hl.dsp.exec_cmd([[grim -g "$(slurp)" ~/Pictures/Screenshots/$(date +'%Y%m%d_%H%M%S').png]]))
-- hl.bind("SHIFT + Print", hl.dsp.exec_cmd([[mkdir -p ~/Pictures/Screenshots && grim -g "$(slurp)" ~/Pictures/Screenshots/$(date +'%Y%m%d_%H%M%S').png && notify-send "Screenshot saved"]]))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd([[mkdir -p ~/Pictures/Screenshots && notify-send "ディレクトリ作成" "Screenshots ディレクトリを確認" && grim -g "$(slurp)" ~/Pictures/Screenshots/$(date +'%Y%m%d_%H%M%S').png && notify-send "Screenshot" "保存完了"]]))

---- メディアコントロール ----
-- 音量調整（旧 bindel: 長押しリピート + ロック中も有効 / repeat & works on lockscreen）
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true, locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { repeating = true, locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })

-- 再生コントロール（playerctl。旧 bindl: ロック中も有効 / works on lockscreen）
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- 画面の明るさ調整（旧 bindel）
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set 5%+"), { repeating = true, locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { repeating = true, locked = true })
