return {
  {
    'AndrewRadev/linediff.vim',
    cmd = { 'Linediff' }, -- "Linediff" コマンドを実行するとプラグインが読み込まれる
    config = function()
      -- linediffのカスタムコマンドの設定
      vim.g.linediff_first_buffer_command = 'leftabove new'
      vim.g.linediff_second_buffer_command = 'rightbelow vertical new'

      -- Linediffのバッファが準備できたときにマッピングを設定
      vim.api.nvim_create_augroup('LineDiff', { clear = true })
      vim.api.nvim_create_autocmd('User', {
        pattern = 'LinediffBufferReady',
        group = 'LineDiff',
        callback = function()
          vim.api.nvim_buf_set_keymap(0, 'n', 'q', ':<C-u>LinediffReset<CR>', { noremap = true, silent = true })
        end,
      })
    end,
  },
}
