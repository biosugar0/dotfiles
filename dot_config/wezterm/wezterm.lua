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
-- パスワード入力検知を無効化。
-- tmux の raw モード(echo off)を「パスワード入力中」と誤検知し、
-- macOS Secure Input を掴んだままにする挙動を防ぐ(AeroSpace のホットキー奪取対策)。
config.detect_password_input = false
config.front_end = 'WebGpu'
config.adjust_window_size_when_changing_font_size = true

-- フォントの設定 (Nerd Font fallback)
config.font = wezterm.font_with_fallback({
  'Monaspace Neon',
  'Hack Nerd Font',
})
config.font_size = 15.0

-- colors
config.color_scheme = 'iceberg-dark'

-- 右上ステータス: CPU / バッテリー / 時刻 (tmux status-right の後継。herdr には status bar が無い)
-- run_child_process は同期実行で GUI スレッドを塞ぐため、更新は 5 秒間隔 (tmux status-interval 相当)
config.status_update_interval = 5000

local status_palette = {
  fg = '#c6c8d1', -- iceberg-dark
  dim = '#6b7089',
  green = '#b4be82',
  yellow = '#e2a478',
  red = '#e27878',
}

-- ps の %cpu 合計は全コア分なので論理コア数で正規化する
local ncpu = 8
do
  local ok, out = wezterm.run_child_process({ '/usr/sbin/sysctl', '-n', 'hw.ncpu' })
  if ok then
    ncpu = tonumber(out:match('%d+')) or ncpu
  end
end

local function cpu_cell()
  local ok, out = wezterm.run_child_process({
    '/bin/sh',
    '-c',
    "/bin/ps -A -o %cpu= | awk '{s+=$1} END {if (NR > 0) printf \"%.0f\", s}'",
  })
  local total = ok and tonumber(out) or nil
  if not total then
    return status_palette.dim, '\u{f2db} --%'
  end
  local pct = math.floor(total / ncpu + 0.5)
  local color = status_palette.fg
  if pct >= 80 then
    color = status_palette.red
  elseif pct >= 50 then
    color = status_palette.yellow
  end
  return color, string.format('\u{f2db} %d%%', pct)
end

local function battery_cell()
  -- battery_info はバッテリー非搭載環境で空になる
  local ok, info = pcall(wezterm.battery_info)
  local bat = ok and info[1] or nil
  if not bat then
    return nil
  end
  local pct = math.floor(bat.state_of_charge * 100 + 0.5)
  local icons = { '\u{f244}', '\u{f243}', '\u{f242}', '\u{f241}', '\u{f240}' }
  local icon = icons[math.min(5, math.floor(pct / 25) + 1)]
  local color = status_palette.fg
  if bat.state == 'Charging' then
    icon = '\u{f0e7}' .. icon
    color = status_palette.green
  elseif pct <= 20 then
    color = status_palette.red
  end
  return color, string.format('%s %d%%', icon, pct)
end

local function right_status_cells()
  local cells = {}
  local function push(color, text)
    table.insert(cells, { Foreground = { Color = color } })
    table.insert(cells, { Text = text })
  end
  local cpu_color, cpu_text = cpu_cell()
  push(cpu_color, ' ' .. cpu_text .. ' ')
  local bat_color, bat_text = battery_cell()
  if bat_text then
    push(status_palette.dim, '│')
    push(bat_color, ' ' .. bat_text .. ' ')
  end
  push(status_palette.dim, '│')
  push(status_palette.fg, wezterm.strftime(' %Y-%m-%d(%a) %H:%M '))
  return cells
end

wezterm.on('update-right-status', function(window, pane)
  window:set_right_status(wezterm.format(right_status_cells()))
end)

-- keybinds
-- デフォルトのkeybindを無効化
config.disable_default_key_bindings = true
-- `keybinds.lua`を読み込み
local keybind = require('keybinds')
-- keybindの設定
config.keys = keybind.keys
config.key_tables = keybind.key_tables

-- 1タブ (herdr 常用) でもタブバーを出す。右上の時刻表示がバーごと消えるため
config.hide_tab_bar_if_only_one_tab = false
config.use_fancy_tab_bar = false
-- padding 0
config.window_padding = {
  left = 0,
  right = 0,
  top = 0,
  bottom = 0,
}
config.colors = {
  background = '#000000',
}

-- 透過設定
config.window_background_opacity = 0.85
config.text_background_opacity = 0.9
config.macos_window_background_blur = 10

-- 設定を wezterm に返す
return config
