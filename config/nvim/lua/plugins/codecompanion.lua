return {
  {
    'olimorris/codecompanion.nvim',
    event = 'VeryLazy',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-treesitter/nvim-treesitter',
      'nvim-telescope/telescope.nvim',
      'zbirenbaum/copilot.lua',
      { 'MeanderingProgrammer/render-markdown.nvim', ft = { 'markdown', 'codecompanion' } },
    },
    keys = {
      {
        '<leader>cc',
        '<cmd>CodeCompanionActions<cr>',
        mode = { 'n', 'v' },
        noremap = true,
        silent = true,
        desc = 'CodeCompanion actions',
      },
      {
        '<leader>ca',
        '<cmd>CodeCompanionChat Toggle<cr>',
        mode = { 'n', 'v' },
        noremap = true,
        silent = true,
        desc = 'CodeCompanion chat',
      },
      {
        '<leader>cd',
        '<cmd>CodeCompanionChat Add<cr>',
        mode = 'v',
        noremap = true,
        silent = true,
        desc = 'CodeCompanion add to chat',
      },
    },
    opts = {
      adapters = {
        copilot = function()
          return require('codecompanion.adapters').extend('copilot', {
            schema = {
              model = {
                default = 'claude-3.5-sonnet',
              },
            },
          })
        end,
      },
      strategies = {
        inline = {
          adapter = 'copilot',
        },
        agent = {
          adapter = 'copilot',
        },
        chat = {
          adapter = 'copilot',
          roles = {
            llm = '  ',
            user = '  ',
          },
          keymaps = {
            close = {
              modes = {
                n = 'q',
              },
              index = 3,
              callback = 'keymaps.close',
              description = 'Close Chat',
            },
            stop = {
              modes = {
                n = '<C-c',
              },
              index = 4,
              callback = 'keymaps.stop',
              description = 'Stop Request',
            },
          },
        },
      },
    },
    config = function(_, opts)
      require('codecompanion').setup(opts)
    end,
  },
}
