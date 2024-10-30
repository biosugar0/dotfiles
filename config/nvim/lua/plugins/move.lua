return {
  {
    'haya14busa/vim-edgemotion',
    keys = {
      { '<Leader>j', mode = { 'n', 'o', 'x' } },
      { '<Leader>k', mode = { 'n', 'o', 'x' } },
    },
    config = function()
      vim.keymap.set({ 'n' }, '<Leader>j', function()
        return 'm`' .. vim.fn['edgemotion#move'](1)
      end, { silent = true, expr = true })
      vim.keymap.set({ 'o', 'x' }, '<Leader>j', function()
        return vim.fn['edgemotion#move'](1)
      end, { silent = true, expr = true })
      vim.keymap.set({ 'n', 'o', 'x' }, '<Leader>k', function()
        return vim.fn['edgemotion#move'](0)
      end, { silent = true, expr = true })
    end,
  },
  {
    'hrsh7th/vim-eft',
    keys = {
      { '<Plug>(eft-f)', mode = { 'n', 'o', 'x' } },
      { '<Plug>(eft-F)', mode = { 'n', 'o', 'x' } },
      { '<Plug>(eft-t)', mode = { 'n', 'o', 'x' } },
      { '<Plug>(eft-T)', mode = { 'n', 'o', 'x' } },
      { '<Plug>(eft-repeat)', mode = { 'n', 'o', 'x' } },
    },
    init = function()
      local function enable_eft()
        vim.g.eft_enable = true
        vim.keymap.set({ 'n', 'o', 'x' }, ';;', '<Plug>(eft-repeat)')
        vim.keymap.set({ 'n', 'o', 'x' }, 'f', '<Plug>(eft-f)')
        vim.keymap.set({ 'n', 'o', 'x' }, 'F', '<Plug>(eft-F)')
        vim.keymap.set({ 'o', 'x' }, 't', '<Plug>(eft-t)')
        vim.keymap.set({ 'o', 'x' }, 'T', '<Plug>(eft-T)')
      end
      enable_eft()
    end,
  },
  {
    'yuki-yano/fuzzy-motion.vim',
    lazy = false,
    dependencies = {
      { 'vim-denops/denops.vim' },
      { 'lambdalisue/kensaku.vim' },
    },
    cmd = { 'FuzzyMotion' },
    init = function()
      vim.g.fuzzy_motion_matchers = { 'fzf', 'kensaku' }
      vim.keymap.set({ 'n', 'x' }, '<Leader>s', '<Cmd>FuzzyMotion<CR>')
    end,
  },
  { 'lambdalisue/vim-kensaku' },
  {
    'ahmedkhalf/project.nvim',
    event = 'BufRead', -- バッファが読み込まれる際にプラグインを読み込む
    config = function()
      require('project_nvim').setup({
        manual_mode = false, -- 手動モードを無効化
        detection_methods = { 'lsp', 'pattern' }, -- LSP または pattern による検出
        patterns = { '.git', 'Makefile', 'package.json', 'go.mod', 'pyproject.toml' }, -- プロジェクトルートとして検出するファイル
        ignore_lsp = {}, -- 無視するLSPなし
        exclude_dirs = {}, -- 除外するディレクトリなし
        show_hidden = false, -- 隠しファイルは表示しない
        silent_chdir = false, -- ディレクトリの変更を通知する
        scope_chdir = 'global', -- ディレクトリ変更のスコープをグローバルに設定
        datapath = vim.fn.stdpath('data'), -- データパス
      })
    end,
  },
  {
    'haya14busa/vim-asterisk',
    event = 'VeryLazy', -- マッピングが使用される際に遅延読み込み
    config = function()
      -- 'nvim-hlslens' のセットアップ
      require('hlslens').setup()

      -- キーマッピングの設定
      local opts = { noremap = true, silent = true }
      vim.api.nvim_set_keymap('n', '*', "<Plug>(asterisk-z*)<Cmd>lua require('hlslens').start()<CR>", opts)
      vim.api.nvim_set_keymap('n', '#', "<Plug>(asterisk-z#)<Cmd>lua require('hlslens').start()<CR>", opts)
      vim.api.nvim_set_keymap('n', 'g*', "<Plug>(asterisk-gz*)<Cmd>lua require('hlslens').start()<CR>", opts)
      vim.api.nvim_set_keymap('n', 'g#', "<Plug>(asterisk-gz#)<Cmd>lua require('hlslens').start()<CR>", opts)

      -- さらに便利な hlslens + vim-asterisk の連携設定
      -- * や # で検索後、結果を見ながら表示する
      vim.api.nvim_set_keymap(
        'n',
        'n',
        [[<Cmd>execute('normal! ' . v:count1 . 'n')<CR><Cmd>lua require('hlslens').start()<CR>]],
        opts
      )
      vim.api.nvim_set_keymap(
        'n',
        'N',
        [[<Cmd>execute('normal! ' . v:count1 . 'N')<CR><Cmd>lua require('hlslens').start()<CR>]],
        opts
      )
    end,
    dependencies = {
      {
        'kevinhwang91/nvim-hlslens', -- 'nvim-hlslens' プラグイン
        config = true, -- hlslens の設定も自動的に読み込む
      },
    },
  },
  {
    'christoomey/vim-tmux-navigator',
    keys = {
      { '<C-w>h', '<cmd>TmuxNavigateLeft<CR>', mode = 'n', silent = true },
      { '<C-w>j', '<cmd>TmuxNavigateDown<CR>', mode = 'n', silent = true },
      { '<C-w>k', '<cmd>TmuxNavigateUp<CR>', mode = 'n', silent = true },
      { '<C-w>l', '<cmd>TmuxNavigateRight<CR>', mode = 'n', silent = true },
      { '<C-w>\\', '<cmd>TmuxNavigatePrevious<CR>', mode = 'n', silent = true },
    },
  },
}
