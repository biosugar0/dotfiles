return {
  {
    'vim-skk/skkeleton',
    dependencies = {
      { 'vim-denops/denops.vim' },
      { 'skk-dev/dict', lazy = true },
      { 'tani/vim-artemis' },
    },
    event = { 'InsertEnter' },
    keys = { '<C-j>', mode = 'i' },
    init = function()
      local vimx = require('artemis')

      vim.keymap.set({ 'i' }, '<C-j>', '<Plug>(skkeleton-toggle)')
      vim.api.nvim_create_autocmd({ 'User' }, {
        pattern = { 'skkeleton-initialize-pre' },
        callback = function()
          vimx.fn.skkeleton.config({
            eggLikeNewline = true,
            showCandidatesCount = 5,
            globalDictionaries = {
              { vim.fn.stdpath('cache') .. '/lazy/dict/SKK-JISYO.L', 'euc-jp' },
              { vim.fn.stdpath('cache') .. '/lazy/dict/SKK-JISYO.emoji', 'utf-8' },
              { vim.fn.stdpath('cache') .. '/lazy/dict/SKK-JISYO.propernoun', 'euc-jp' },
              { vim.fn.stdpath('cache') .. '/lazy/dict/SKK-JISYO.hukugougo', 'euc-jp' },
              { vim.fn.stdpath('cache') .. '/lazy/dict/SKK-JISYO.edict', 'utf-8' },
              { vim.fn.stdpath('cache') .. '/lazy/dict/SKK-JISYO.edict2', 'utf-8' },
              { vim.fn.stdpath('cache') .. '/lazy/dict/SKK-JISYO.mazegaki', 'euc-jp' },
            },
            selectCandidateKeys = 'asdfjkl',
          })
        end,
      })
      vim.api.nvim_create_autocmd({ 'User' }, {
        pattern = { 'DenopsPluginPost:skkeleton' },
        callback = function()
          vimx.fn.skkeleton.initialize()
        end,
      })
    end,
  },
}
