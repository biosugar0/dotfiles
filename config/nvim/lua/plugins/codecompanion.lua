return {
  {
    'olimorris/codecompanion.nvim',
    event = 'VeryLazy',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-treesitter/nvim-treesitter',
      'nvim-telescope/telescope.nvim',
      'zbirenbaum/copilot.lua',
      {
        'echasnovski/mini.diff',
        config = function()
          local diff = require('mini.diff')
          diff.setup({
            -- Disabled by default
            source = diff.gen_source.none(),
          })
        end,
      },
      { 'MeanderingProgrammer/render-markdown.nvim', ft = { 'markdown', 'codecompanion' } },
    },
    -- Buffer commands for CodeCompanion plugin
    keys = {
      { 'cc', '<cmd>CodeCompanion<cr>', mode = { 'n', 'v' } }, -- Open companion
      { 'ccc', '<cmd>CodeCompanionChat<cr>', mode = { 'n', 'v' } }, -- Start chat
      { 'cca', '<cmd>CodeCompanionActions<cr>', mode = { 'n', 'v' } }, -- List actions
    },
    opts = {
      display = {
        diff = {
          provider = 'mini_diff',
        },
      },
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
