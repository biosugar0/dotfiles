return {
  {
    'machakann/vim-sandwich',
    event = 'VeryLazy',
    config = function()
      -- 設定の追加
      vim.g.sandwich_no_default_key_mappings = 1

      -- add
      vim.api.nvim_set_keymap('n', 'sa', '<Plug>(sandwich-add)', {})
      vim.api.nvim_set_keymap('x', 'sa', '<Plug>(sandwich-add)', {})
      vim.api.nvim_set_keymap('o', 'sa', '<Plug>(sandwich-add)', {})

      -- delete
      vim.api.nvim_set_keymap('n', 'sd', '<Plug>(sandwich-delete)', {})
      vim.api.nvim_set_keymap('x', 'sd', '<Plug>(sandwich-delete)', {})
      vim.api.nvim_set_keymap('n', 'sdb', '<Plug>(sandwich-delete-auto)', {})

      -- replace
      vim.api.nvim_set_keymap('n', 'sr', '<Plug>(sandwich-replace)', {})
      vim.api.nvim_set_keymap('x', 'sr', '<Plug>(sandwich-replace)', {})
      vim.api.nvim_set_keymap('n', 'srb', '<Plug>(sandwich-replace-auto)', {})

      -- text object
      vim.api.nvim_set_keymap('o', 'ib', '<Plug>(textobj-sandwich-auto-i)', {})
      vim.api.nvim_set_keymap('x', 'ib', '<Plug>(textobj-sandwich-auto-i)', {})
      vim.api.nvim_set_keymap('o', 'ab', '<Plug>(textobj-sandwich-auto-a)', {})
      vim.api.nvim_set_keymap('x', 'ab', '<Plug>(textobj-sandwich-auto-a)', {})

      -- operator#sandwichの設定
      vim.cmd([[
        call operator#sandwich#set('add', 'char', 'skip_space', 1)
      ]])
    end,
  },
}
