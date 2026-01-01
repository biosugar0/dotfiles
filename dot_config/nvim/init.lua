vim.loader.enable()

vim.env.VIMHOME = vim.fn.expand('<sfile>:p:h')
vim.g.rc_dir = vim.env.VIMHOME
vim.g.mapleader = ' ' -- デフォルトのマップリーダーをスペースに変更
vim.g.maplocalleader = ' ' -- デフォルトのローカルマップリーダーをスペースに変更
local set = vim.opt

if vim.fn.has('vim_starting') == 1 then
  set.encoding = 'utf-8'

  vim.g.colorterm = os.getenv('COLORTERM')
  if vim.fn.exists('+termguicolors') == 1 then
    vim.o.termguicolors = true -- true color
  end
  vim.g.did_install_default_menus = 1
  vim.g.did_install_syntax_menu = 1
  vim.g.no_gvimrc_example = 1
  vim.g.no_vimrc_example = 1
  vim.g.skip_loading_mswin = 1
  -- ビジュアルベルを無効化
  set.visualbell = false
  if vim.fn.exists('&belloff') then
    set.belloff = 'all'
  end
  -- タイムアウトを有効化
  set.timeout = true
  set.ttimeout = true
  set.ttimeoutlen = 100
  set.updatetime = 800
  vim.env.CACHE = vim.fn.expand('~/.cache')
end

require('rc.plugin_manager').lazy_init()
require('rc.preload')
-- -- NOTE: lazy.nvim auto load lua/plugins/config.lua
-- --       unnecessary `require('plugins/config')`
-- --       config.lua load base settings with cache. (from lazy.nvim)
-- --         - lua/options.lua
-- --         - lua/func.lua
-- --         - lua/highlight.lua
require('rc.plugin_manager').lazy_setup()
set.secure = true -- セキュアモード (セキュアモードでは、外部からのコマンド実行を禁止)
