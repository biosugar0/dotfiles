-- wezterm APIを読み込む
local wezterm = require('wezterm')

-- 設定を保持する変数
local config = wezterm.config_builder()

config.use_ime = true
config.ime_preedit_rendering = 'Builtin'
config.macos_forward_to_ime_modifier_mask = 'SHIFT|CTRL'
config.keys = {
  { key = 'q', mods = 'CTRL', action = wezterm.action({ SendString = '\x11' }) },
}
config.exit_behavior = 'CloseOnCleanExit'
config.automatically_reload_config = false
wezterm.on('window-config-reloaded', function(window, pane)
  wezterm.log_info('the config was reloaded for this window!')
end)
config.audible_bell = 'Disabled'
config.scrollback_lines = 100000
config.use_dead_keys = false
config.front_end = 'WebGpu'
config.adjust_window_size_when_changing_font_size = true

-- 最初からフルスクリーンで起動
local mux = wezterm.mux
wezterm.on('gui-startup', function(cmd)
  local tab, pane, window = mux.spawn_window(cmd or {})
  window:gui_window():toggle_fullscreen()
end)

-- フォントの設定
config.font = wezterm.font('Monaspace Neon')
config.font_size = 15.0

-- colors
config.color_scheme = 'iceberg-dark'

-- 通知が不要な場合の追加設定
wezterm.on('update-right-status', function(window, pane)
  -- 特定の通知を抑制する設定内容
end)

-- keybinds
-- デフォルトのkeybindを無効化
config.disable_default_key_bindings = true
-- `keybinds.lua`を読み込み
local keybind = require('keybinds')
-- keybindの設定
config.keys = keybind.keys
config.key_tables = keybind.key_tables

config.leader = { key = 'LeftAlt', mods = 'NONE' }
config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false
-- padding 0
config.window_padding = {
  left = 0,
  right = 0,
  top = 0,
  bottom = 0,
}
config.colors = {
  background = '#000000', -- WezTermの背景色を黒に設定
}

-- 設定を wezterm に返す
return config
