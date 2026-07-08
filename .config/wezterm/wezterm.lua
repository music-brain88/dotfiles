-- WezTerm 設定 — native Arch と Windows (WSL2) をこの1枚で賄う。
-- Alacritty の base + windows.toml のビルド時マージは、Lua の実行時分岐で置き換える。
-- WezTerm config — a single file for both native Arch and Windows (WSL2).
-- Runtime branching replaces Alacritty's build-time base + windows.toml merge.

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

local is_windows = wezterm.target_triple:find('windows') ~= nil

-- ---------------------------------------------------------------------------
-- 見た目 / Appearance (Alacritty で使っていた One Dark 系パレットを踏襲)
-- ---------------------------------------------------------------------------
config.colors = {
  foreground = '#abb2bf',
  background = '#1e2127',
  ansi = {
    '#1e2127', -- black
    '#e06c75', -- red
    '#98c379', -- green
    '#d19a66', -- yellow
    '#61afef', -- blue
    '#c678dd', -- magenta
    '#56b6c2', -- cyan
    '#828791', -- white
  },
  brights = {
    '#5c6370', -- bright black
    '#e06c75', -- bright red
    '#98c379', -- bright green
    '#d19a66', -- bright yellow
    '#61afef', -- bright blue
    '#c678dd', -- bright magenta
    '#56b6c2', -- bright cyan
    '#e6efff', -- bright white
  },
}

config.font = wezterm.font 'HackGen35 Console NF'
config.font_size = 14.0
config.window_background_opacity = 0.8

-- タブ・ペイン管理は herdr が担うため、WezTerm 自身のタブバーは出さない
-- herdr owns tabs/panes, so hide WezTerm's own tab bar
config.enable_tab_bar = false
config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }

-- ---------------------------------------------------------------------------
-- シェル / Shell (herdr は既存セッションへ自動アタッチするため分岐不要)
-- ---------------------------------------------------------------------------
if is_windows then
  -- 既定の WSL ディストロ (Arch) に入り、native と同じく fish + herdr を起動する
  -- Enter the default WSL distro (Arch) and start fish + herdr, same as native
  config.default_prog =
    { 'wsl.exe', '--cd', '~', '--', '/usr/bin/fish', '--login', '--command', 'herdr' }
else
  config.default_prog = { '/usr/bin/fish', '--login', '--command', 'herdr' }
end

-- ---------------------------------------------------------------------------
-- キーバインド / Keybindings
-- コピー/ペースト (Ctrl+Shift+C/V)・フォントサイズ (Ctrl+0/=/-)・
-- 新規ウィンドウ (Ctrl+Shift+N) は WezTerm の既定が Alacritty 設定と一致するため定義しない
-- Copy/paste, font size and new-window defaults already match the old
-- Alacritty bindings, so only the differences are declared here
-- ---------------------------------------------------------------------------
config.keys = {
  -- Claude Code 等の改行 (ESC + CR)。既定では Alt+Enter がフルスクリーン切替に
  -- 取られるため明示バインドで上書きし、Linux と同一挙動にする
  -- Newline (ESC + CR) for Claude Code etc. Alt+Enter defaults to fullscreen
  -- toggle, so override it explicitly to match Linux behavior
  { key = 'Enter', mods = 'ALT', action = wezterm.action.SendString '\x1b\r' },
  { key = 'F11', action = wezterm.action.ToggleFullScreen },
}

-- 日本語 IME (Windows はネイティブ IME、native Arch は fcitx5)
-- Japanese IME (native Windows IME on Windows, fcitx5 on Arch)
config.use_ime = true

return config
