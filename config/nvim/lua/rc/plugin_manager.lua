local misc_icons = require('rc.font').misc_icons

local M = {}

local function confirm(manager)
  return vim.fn.confirm('Install ' .. manager .. ' or Launch Neovim immediately', '&Yes\n&No', 1) == 1
end

local function install_lazy(path)
  vim.fn.system({
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    path,
  })
  vim.opt.rtp:prepend(path)
end

local lazy_init_default_opts = {
  lazy_path = vim.fn.stdpath('cache') .. '/lazy/lazy.nvim',
}

M.lazy_init = function(opts)
  opts = vim.tbl_deep_extend('force', lazy_init_default_opts, opts or {})
  local lazy_path = opts.lazy_path
  local installed_lazy = vim.loop.fs_stat(lazy_path)

  if not installed_lazy and confirm('lazy.nvim') then
    install_lazy(lazy_path)
  elseif installed_lazy then
    vim.opt.rtp:prepend(lazy_path)
  end
end

local lazy_setup_default_opts = {
  root = vim.fn.stdpath('cache') .. '/lazy',
  defaults = {
    lazy = true,
  },
  concurrency = 100,
  checker = {
    enable = true,
    concurrency = 100,
  },
  dev = { path = '~/ghq/github.com/biosugar0' },
  ui = {
    border = 'rounded',
    icons = {
      lazy = misc_icons.lazy .. ' ',
      runtime = misc_icons.vim,
      cmd = misc_icons.cmd,
      import = misc_icons.file,
      ft = misc_icons.folder,
    },
  },
  performance = {
    rtp = {
      disabled_plugins = {
        '2html_plugin',
        'getscript',
        'getscriptPlugin',
        'gzip',
        'netrw',
        'netrwFileHandlers',
        'netrwPlugin',
        'netrwSettings',
        'rrhelper',
        'tar',
        'tarPlugin',
        'vimball',
        'vimballPlugin',
        'zip',
        'zipPlugin',
        'man',
        'tutor_mode_plugin',
      },
    },
  },
}
M.lazy_setup = function(opts)
  opts = vim.tbl_deep_extend('force', lazy_setup_default_opts, opts or {})
  require('lazy').setup('plugins', opts)
end

return M
