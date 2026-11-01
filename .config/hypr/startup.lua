-------------------
---- AUTOSTART ----
-------------------
-- 旧 startup.conf の exec-once を、Hyprland 0.57 の hyprland.start イベントに写したもの。
-- hyprland.start は起動時に 1 回だけ発火する(`hyprctl reload` では発火しない)。
-- Ported from the exec-once lines of the former startup.conf onto the hyprland.start event (Hyprland 0.57+).
-- hyprland.start fires once at startup only; `hyprctl reload` does not fire it again.
hl.on("hyprland.start", function ()
  -- systemd に Wayland 環境変数を渡す（session target の起動より先に実行すること）
  -- import env vars into systemd BEFORE starting the session target
  hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")

  -- systemd 管理のセッション開始。graphical-session.target が活性化され、
  -- waybar.service（クラッシュ時は Restart=on-failure で自動復活）などが起動する
  hl.exec_cmd("systemctl --user start hyprland-session.target")

  -- 自動起動するアプリケーション
  hl.exec_cmd("hyprpaper")
  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")

  -- アイドル管理（自動ロック・画面消灯）/ idle management
  hl.exec_cmd("hypridle")

  -- IME
  hl.exec_cmd("fcitx5 -d")

  -- 通知デーモン
  hl.exec_cmd("mako")

  -- polkit
  hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")

  -- hyprpm 管理プラグイン(hyprtasking #549)の自動ロード。
  -- -n は成功時にも通知を出すフラグ(警告・エラーは -n の有無に関係なく常に通知される)
  -- プラグインが読み込まれると Hyprland は設定を読み直すので、plugins.lua の設定ブロックはその時点で適用される
  -- autoload hyprpm-managed plugins (hyprtasking, #549); -n adds a success notification
  -- (warnings/errors always notify regardless of the flag)
  -- Hyprland reloads the config after a plugin loads, so the block in plugins.lua is applied at that point
  hl.exec_cmd("hyprpm reload -n")
end)
