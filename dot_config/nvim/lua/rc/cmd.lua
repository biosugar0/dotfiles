local function open_by_cursor()
  local path = vim.fn.expand('%:p')
  local line = vim.fn.line('.')
  -- コマンド実行結果を表示することなく実行
  vim.cmd('silent! !cursor --g ' .. path .. ':' .. line)
end

vim.api.nvim_create_user_command('Cursor', open_by_cursor, {range = true})
