return {
  {
    'thinca/vim-qfreplace',
    ft = 'qf', -- クイックフィックスリストのファイルタイプが開かれたときに読み込み
    config = function()
      -- クイックフィックスリスト内で `r` キーで `Qfreplace` を実行
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'qf',
        callback = function()
          vim.api.nvim_buf_set_keymap(0, 'n', 'r', '<Cmd>Qfreplace<CR>', { noremap = true, silent = true })
        end,
      })
    end,
  },
  {
    'yssl/QFEnter',
    ft = 'qf', -- クイックフィックスリストのファイルタイプが開かれたときに読み込み
  },
}
