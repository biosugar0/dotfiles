return {
  {
    'lewis6991/gitsigns.nvim',
    event = 'VimEnter',
    config = function()
      require('gitsigns').setup({
        signs = {
          add = { text = '+' },
          change = { text = '│' },
          delete = { text = '_' },
          topdelete = { text = '‾' },
          changedelete = { text = '~' },
          untracked = { text = '┆' },
        },
        signs_staged = {
          add = { text = '+' },
          change = { text = '│' },
          delete = { text = '_' },
          topdelete = { text = '‾' },
          changedelete = { text = '~' },
          untracked = { text = '┆' },
        },
        signs_staged_enable = true,
        signcolumn = true,
        numhl = false,
        linehl = false,
        word_diff = false,
        watch_gitdir = {
          follow_files = true,
        },
        auto_attach = true,
        attach_to_untracked = false,
        current_line_blame = false,
        current_line_blame_opts = {
          virt_text = true,
          virt_text_pos = 'eol',
          delay = 1000,
          ignore_whitespace = false,
          virt_text_priority = 100,
        },
        current_line_blame_formatter = '<author>, <author_time:%R> - <summary>',
        sign_priority = 6,
        update_debounce = 100,
        status_formatter = nil,
        max_file_length = 40000,
        preview_config = {
          border = 'single',
          style = 'minimal',
          relative = 'cursor',
          row = 0,
          col = 1,
        },
        on_attach = function(bufnr)
          local gitsigns = require('gitsigns')

          local function map(mode, l, r, opts)
            opts = opts or {}
            opts.buffer = bufnr
            vim.keymap.set(mode, l, r, opts)
          end

          -- Navigation
          map('n', ']c', function()
            if vim.wo.diff then
              vim.cmd.normal({ ']c', bang = true })
            else
              gitsigns.nav_hunk('next')
            end
          end)

          map('n', '[c', function()
            if vim.wo.diff then
              vim.cmd.normal({ '[c', bang = true })
            else
              gitsigns.nav_hunk('prev')
            end
          end)

          -- Actions
          map('n', '<leader>hs', gitsigns.stage_hunk)
          map('n', '<leader>hr', gitsigns.reset_hunk)
          map('v', '<leader>hs', function()
            gitsigns.stage_hunk({ vim.fn.line('.'), vim.fn.line('v') })
          end)
          map('v', '<leader>hr', function()
            gitsigns.reset_hunk({ vim.fn.line('.'), vim.fn.line('v') })
          end)
          map('n', '<leader>hS', gitsigns.stage_buffer)
          map('n', '<leader>hu', gitsigns.undo_stage_hunk)
          map('n', '<leader>hR', gitsigns.reset_buffer)
          map('n', '<leader>hp', gitsigns.preview_hunk)
          map('n', '<leader>hb', function()
            gitsigns.blame_line({ full = true })
          end)
          map('n', '<leader>tb', gitsigns.toggle_current_line_blame)
          map('n', '<leader>hd', gitsigns.diffthis)
          map('n', '<leader>hD', function()
            gitsigns.diffthis('~')
          end)
          map('n', '<leader>td', gitsigns.toggle_deleted)

          -- Text object
          map({ 'o', 'x' }, 'ih', ':<C-U>Gitsigns select_hunk<CR>')
        end,
      })
    end,
  },
  {
    'lambdalisue/vim-gin',
    dependencies = {
      'vim-denops/denops.vim',
    },
    event = 'User DenopsReady',
    cmd = {
      'Gin',
      'GinBuffer',
      'GinBranch',
      'GinBrowse',
      'GinCd',
      'GinLcd',
      'GinTcd',
      'GinChaperon',
      'GinDiff',
      'GinEdit',
      'GinLog',
      'GinPatch',
      'GinStatus',
    },
    keys = {
      '<Leader>aa',
      '<Leader>ab',
      '<Leader>ap',
      '<Leader>ac',
      '<Leader>aC',
      '<Leader>al',
      '<Leader>aL',
      '<Leader>ao',
      '<Leader>aw',
    },
    config = function()
      -- Key Mappings
      vim.keymap.set('n', '<Leader>aa', '<Cmd>GinStatus<CR>', { silent = true })
      vim.keymap.set('n', '<Leader>ab', '<Cmd>GinBranch --all<CR>', { silent = true })
      vim.keymap.set('n', '<Leader>ap', '<Cmd>Gin push<CR>', { silent = true })
      vim.keymap.set('n', '<Leader>ac', '<Cmd>Gin commit<CR>', { silent = true })
      vim.keymap.set('n', '<Leader>aC', '<Cmd>Gin commit --amend<CR>', { silent = true })
      vim.keymap.set('n', '<Leader>al', ':<C-u>GinLog<CR>', { silent = true })
      vim.keymap.set('n', '<Leader>aL', ':<C-u>GinLog -- %<CR>', { silent = true })
      vim.keymap.set('n', '<Leader>ao', '<Cmd>GinBrowse<CR>', { silent = true })
      vim.keymap.set('x', '<Leader>ao', ':GinBrowse<CR>', { silent = true })
      vim.keymap.set('n', '<Leader>aw', '<Cmd>GinBrowse --pr<CR>', { silent = true })
      -- Autocommands
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'gin-status',
        callback = function()
          vim.api.nvim_buf_set_keymap(0, 'n', 'c', '<Cmd>Gin commit<CR>', { silent = true })
        end,
      })

      -- gin-branch バッファ用のキーマップ設定
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'gin-branch',
        callback = function()
          vim.api.nvim_buf_set_keymap(0, 'n', 'n', '<Plug>(gin-action-new)', { silent = true, noremap = true })
          vim.api.nvim_buf_set_keymap(0, 'n', 'dd', '<Plug>(gin-action-delete)', { silent = true, noremap = true })
        end,
      })
      -- gins-status バッファ用のキーマップ設定
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'gin-status',
        callback = function()
          vim.api.nvim_buf_set_keymap(0, 'n', 'rr', '<Plug>(gin-action-restore)', { silent = true, noremap = true })
        end,
      })

      vim.api.nvim_create_autocmd('User', {
        pattern = 'GinComponentPost',
        callback = function()
          vim.cmd('redrawtabline')
        end,
      })

      -- Gin specific configurations
      vim.g.gin_proxy_apply_without_confirm = true -- 確認なしで変更を適用
      vim.g.gin_diff_default_args = {
        '++processor=delta --diff-highlight --keep-plus-minus-markers',
      }

      vim.g.gin_branch_default_args = { '--all', '--sort=-committerdate' }
      vim.g.gin_browse_default_args = {
        '--remote=origin',
        '--permalink',
      }
      vim.g.gin_log_default_args = {
        '++emojify',
        '--pretty=%C(yellow)%h%C(reset)%C(auto)%d%C(reset) %s %C(cyan)@%an%C(reset) %C(magenta)[%ar]%C(reset)',
      }
    end,
  },
}
