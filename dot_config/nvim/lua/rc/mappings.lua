-------------------------------------------------------------------------------
-- コマンド       ノーマルモード 挿入モード コマンドラインモード ビジュアルモード
-- map/noremap           @            -              -                  @
-- nmap/nnoremap         @            -              -                  -
-- imap/inoremap         -            @              -                  -
-- cmap/cnoremap         -            -              @                  -
-- vmap/vnoremap         -            -              -                  @
-- map!/noremap!         -            @              @                  -
-------------------------------------------------------------------------------
vim.keymap.set('n', 'ZZ', '<Nop>', { noremap = true })
vim.keymap.set('n', '<C-d>', '<Nop>', { noremap = true })
-- jjをescに
vim.keymap.set('i', 'jj', '<ESC>', { noremap = true, silent = true })
vim.keymap.set('t', '<ESC>', [[<C-\><C-n>]], { noremap = true, silent = true })
vim.keymap.set('c', 'j', [[getcmdline()[getcmdpos()-2] ==# 'j' ? '<BS><C-c>' : 'j']], { noremap = true, expr = true })
-- change window size
vim.keymap.set('n', '<S-Left>', '<C-w><<CR>', { noremap = true })
vim.keymap.set('n', '<S-Right>', '<C-w>><CR>', { noremap = true })
vim.keymap.set('n', '<S-Up>', '<C-w>-<CR>', { noremap = true })
vim.keymap.set('n', '<S-Down>', '<C-w>+<CR>', { noremap = true })
-- herdr pane とのシームレスな window 移動 (旧 tmux + vim-tmux-navigator の後継)。
-- C-h/j/k/l で nvim window を移動し、端まで来たら herdr pane へ越境する。herdr 側
-- (config.toml + scripts/nav.sh) が非 vim pane からの C-h/j/k/l を pane 移動に使い、
-- vim pane では同じ chord をここへ forward してくる。C-w は nvim native のまま温存。
-- vim-tmux-navigator は herdr 非対応のため撤去し、wincmd + `herdr pane focus` で自前実装。
-- HERDR_ENV 未設定 (素の端末) では単なる wincmd として振る舞い、越境しない。
-- nav は normal モード限定 (insert の C-h=backspace(lexima)/C-j=skkeleton と無干渉)。
local herdr_nav_dir = { h = 'left', j = 'down', k = 'up', l = 'right' }
local function herdr_nav(key)
  -- floating/command window からは越境しない (通常 window のみ対象)
  if vim.fn.win_gettype() ~= '' then
    vim.cmd.wincmd(key)
    return
  end
  local prev = vim.api.nvim_get_current_win()
  vim.cmd.wincmd(key)
  if vim.api.nvim_get_current_win() == prev and vim.env.HERDR_ENV then
    -- 基準 pane を自分の pane に固定する (focus 中の pane に依存させない)。
    local cmd = { 'herdr', 'pane', 'focus', '--direction', herdr_nav_dir[key] }
    local pane = vim.env.HERDR_PANE_ID
    if pane and pane ~= '' then
      vim.list_extend(cmd, { '--pane', pane })
    end
    vim.system(cmd)
  end
end
for _, key in ipairs({ 'h', 'j', 'k', 'l' }) do
  vim.keymap.set('n', '<C-' .. key .. '>', function() herdr_nav(key) end,
    { noremap = true, silent = true, desc = 'Move to window/herdr-pane ' .. key })
end
vim.keymap.set('n', '<leader>vn', '<Cmd>setlocal number!<CR>', { replace_keycodes = false, noremap = true })

vim.keymap.set('c', '<C-p>', '<Up>', { noremap = true })
vim.keymap.set('c', '<C-n>', '<Down>', { noremap = true })
vim.keymap.set('c', '<Up>', '<C-p>', { noremap = true })
vim.keymap.set('c', '<Down>', '<C-n>', { noremap = true })
-- turn off highlight on enter twice
vim.keymap.set('n', '<Esc><Esc>', '<Cmd>nohlsearch<CR>', { replace_keycodes = false, noremap = true, silent = true })
-- (旧 <C-l><C-l> nohlsearch は削除。C-l を herdr pane nav に解放。nohlsearch は上の <Esc><Esc> が担保)

-- tab operation
vim.keymap.set('n', 'qq', '<Cmd>tabclose<CR>', { replace_keycodes = false, noremap = true, silent = true })

-- smart zero
vim.keymap.set('n', '0', [[getline('.')[0 : col('.') - 2] =~# '^\s\+$' ? '0' : '^']], { noremap = true, expr = true })

-- macro playback
vim.keymap.set('n', 'Q', '@a')

-- editprompt: EDITPROMPT環境変数がある時のみ有効
if vim.env.EDITPROMPT then
  -- バッファ内容を送信
  vim.keymap.set('n', '<Space>x', function()
    vim.cmd('update')
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local content = table.concat(lines, '\n')
    vim.system({ 'editprompt', 'input', '--', content }, { text = true }, function(obj)
      vim.schedule(function()
        if obj.code == 0 then
          vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
          vim.cmd('silent write')
        else
          vim.notify('editprompt failed: ' .. (obj.stderr or 'unknown error'), vim.log.levels.ERROR)
        end
      end)
    end)
  end, { desc = 'Send to editprompt' })

  -- quote収集内容を挿入
  vim.keymap.set('n', '<Space>d', '<Cmd>r !editprompt dump<CR>', { desc = 'Dump quotes' })
end
