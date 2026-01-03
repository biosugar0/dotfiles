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

-- フォントの設定 (Nerd Font fallback)
config.font = wezterm.font_with_fallback({
  'Monaspace Neon',
  'Hack Nerd Font',
})
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
  background = '#000000',
}

-- 透過設定
config.window_background_opacity = 0.85
config.text_background_opacity = 0.9
config.macos_window_background_blur = 10

-- ウィンドウ中央配置
if wezterm.gui then
  local function normalize_window(window)
    if not window then
      return nil
    end
    if window.gui_window then
      local ok, gui_window = pcall(function()
        return window:gui_window()
      end)
      if ok and gui_window then
        window = gui_window
      end
    end
    if not window.get_dimensions then
      return nil
    end
    return window
  end

  local function center_on_main_display(window, attempt)
    attempt = attempt or 1
    if attempt > 6 then
      return
    end

    window = normalize_window(window)
    if not window then
      return
    end

    local screens = wezterm.gui.screens()
    if not screens then
      return
    end

    local main_screen = screens.main or screens.active
    if not main_screen then
      return
    end

    local dimensions = window:get_dimensions()
    if not dimensions or dimensions.is_full_screen then
      wezterm.time.call_after(0.1 * attempt, function()
        center_on_main_display(window, attempt + 1)
      end)
      return
    end

    if dimensions.pixel_width > 0 and dimensions.pixel_height > 0 then
      local centered_x = main_screen.x + math.floor((main_screen.width - dimensions.pixel_width) / 2)
      local centered_y = main_screen.y + math.floor((main_screen.height - dimensions.pixel_height) / 2)
      window:set_position(centered_x, centered_y)
    end

    if attempt < 6 then
      wezterm.time.call_after(0.1 * attempt, function()
        center_on_main_display(window, attempt + 1)
      end)
    end
  end

  wezterm.on('window-config-reloaded', function(window, _)
    center_on_main_display(window)
  end)
end

-- 設定を wezterm に返す
return config
