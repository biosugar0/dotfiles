local misc_icons = require('rc.font').misc_icons
return {
  -- Lua開発を強化するNeodevプラグイン
  {
    'folke/neodev.nvim',
    config = function()
      require('neodev').setup()
    end,
  },
  -- SchemaStoreプラグインの追加
  {
    'b0o/schemastore.nvim',
    version = false,
  },
  -- LSP設定
  {
    'neovim/nvim-lspconfig',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = {
      { 'williamboman/mason-lspconfig.nvim' },
      { 'williamboman/mason.nvim' },
      { 'folke/neodev.nvim' },
      { 'b0o/schemastore.nvim' },
      { 'hrsh7th/cmp-nvim-lsp' },
      { 'j-hui/fidget.nvim' },
      { 'folke/trouble.nvim' },
    },
    config = function()
      local lspconfig = require('lspconfig')
      local mason_lspconfig = require('mason-lspconfig')

      -- Capabilitiesの設定
      local capabilities = vim.lsp.protocol.make_client_capabilities()
      capabilities.textDocument.completion.completionItem.snippetSupport = true
      capabilities.textDocument.completion.completionItem.resolveSupport = {
        properties = {
          'documentation',
          'detail',
          'additionalTextEdits',
        },
      }
      capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

      -- Neodevのセットアップ
      require('neodev').setup()
      -- 診断メッセージの表示設定を改善
      vim.diagnostic.config({
        virtual_text = {
          -- 長い診断メッセージを複数行に分割する
          format = function(diagnostic)
            local max_width = vim.api.nvim_win_get_width(0) - 10 -- ウィンドウ幅に基づく余白
            local message = diagnostic.message
            local lines = {}
            while #message > max_width do
              -- 単語単位で改行するためにスペースを探す
              local break_pos = message:sub(1, max_width):match('.*()%s+%S+$')
              if not break_pos then
                break_pos = max_width
              end
              table.insert(lines, message:sub(1, break_pos))
              message = message:sub(break_pos + 1)
            end
            table.insert(lines, message)
            return table.concat(lines, '\n')
          end,
        },
        float = {
          -- フロートウィンドウのボーダーを設定
          border = 'rounded',
          focusable = false,
          style = 'minimal',
        },
        signs = true,
        underline = true,
        severity_sort = true, -- 診断の重大度でソート
      })
      vim.keymap.set('n', '<leader>e', function()
        vim.diagnostic.open_float(nil, { focusable = false, border = 'rounded' })
      end, { noremap = true, silent = true })

      -- LSPサーバーの設定
      local servers = {
        'bashls', -- Bash
        'gopls', -- Go
        'lua_ls', -- Lua
        'pyright', -- Python
        'yamlls', -- YAML
        'ts_ls', -- TypeScript
        'terraformls', -- Terraform
      }

      -- 各LSPサーバーの個別設定
      local settings = {
        yamlls = {
          yaml = {
            keyOrdering = false,
            schemas = require('schemastore').yaml.schemas(),
          },
        },
        gopls = {
          gopls = {
            usePlaceholders = true,
            completeUnimported = true,
            staticcheck = true,
            analyses = {
              unusedparams = true,
              unreachable = true,
            },
          },
        },
        pyright = {
          python = {
            analysis = {
              autoSearchPaths = true,
              useLibraryCodeForTypes = true,
              diagnosticMode = 'workspace',
              typeCheckingMode = 'off',
            },
          },
        },
        lua_ls = {
          Lua = {
            runtime = {
              version = 'LuaJIT',
              path = vim.split(package.path, ';'),
            },
            diagnostics = {
              globals = { 'vim' },
            },
            workspace = {
              library = vim.api.nvim_get_runtime_file('', true),
              checkThirdParty = false,
            },
            telemetry = {
              enable = false,
            },
          },
        },
        ts_ls = {},
      }

      -- LSPハンドラーの設定（ボーダー付き）
      local border = {
        { '╭', 'FloatBorder' },
        { '─', 'FloatBorder' },
        { '╮', 'FloatBorder' },
        { '│', 'FloatBorder' },
        { '╯', 'FloatBorder' },
        { '─', 'FloatBorder' },
        { '╰', 'FloatBorder' },
        { '│', 'FloatBorder' },
      }

      local handlers = {
        ['textDocument/hover'] = vim.lsp.with(vim.lsp.handlers.hover, { border = border }),
        ['textDocument/signatureHelp'] = vim.lsp.with(vim.lsp.handlers.signature_help, { border = border }),
      }

      -- 共通のon_attach関数
      local on_attach = function(client, bufnr)
        if client.name == 'ts_ls' then
          client.server_capabilities.documentFormattingProvider = false
          client.server_capabilities.documentRangeFormattingProvider = false
        end
        local bufopts = { noremap = true, silent = true, buffer = bufnr }
        vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bufopts)
        vim.keymap.set('n', 'K', vim.lsp.buf.hover, bufopts)
        vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, bufopts)
        vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, bufopts)
        vim.keymap.set('n', 'gr', vim.lsp.buf.rename, bufopts)
        vim.keymap.set('n', 'gD', vim.lsp.buf.references, bufopts)
        vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, bufopts)
        vim.keymap.set('n', ']d', vim.diagnostic.goto_next, bufopts)
        vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, bufopts)

        -- LSP診断メッセージをヤンクする設定
        vim.keymap.set('n', '<leader>yd', function()
          local diagnostics = vim.diagnostic.get(0, { lnum = vim.fn.line('.') - 1 })
          if #diagnostics > 0 then
            local message = diagnostics[1].message
            vim.fn.setreg('+', message) -- クリップボードにコピー
          end
        end, bufopts)
      end

      -- Mason-lspconfigのセットアップ
      mason_lspconfig.setup({
        ensure_installed = servers,
        automatic_installation = true,
      })

      -- LSPサーバーのセットアップ
      for _, server in ipairs(servers) do
        local opts = {
          on_attach = on_attach,
          capabilities = capabilities,
          settings = settings[server],
          handlers = handlers,
        }
        lspconfig[server].setup(opts)
      end
    end,
  },
  -- MasonによるLSPサーバー管理
  {
    'williamboman/mason.nvim',
    build = ':MasonUpdate',
    config = function()
      require('mason').setup()
    end,
  },
  {
    'williamboman/mason-lspconfig.nvim',
    dependencies = { 'williamboman/mason.nvim' },
  },
  -- フォーマッターとリンターの設定
  {
    'nvimtools/none-ls.nvim',
    event = 'BufReadPre',
    dependencies = { 'mason.nvim', 'nvim-lua/plenary.nvim', 'nvimtools/none-ls-extras.nvim' },
    config = function()
      local null_ls = require('null-ls')

      -- Null-ls formatting helper functions
      local null_ls_formatting = function(bufnr)
        -- If the null_ls formatter is available, use it.
        vim.lsp.buf.format({
          filter = function(client)
            return client.name == 'null-ls'
          end,
          bufnr = bufnr,
        })
      end

      local function is_null_ls_formatter_available(bufnr)
        local clients = vim.lsp.get_active_clients({ bufnr = bufnr })
        for _, client in ipairs(clients) do
          if client.name == 'null-ls' and client.supports_method('textDocument/formatting') then
            return true
          end
        end
        return false
      end
      local formatgroup = vim.api.nvim_create_augroup('LspFormatting', {})

      null_ls.setup({
        sources = {
          -- フォーマッター
          null_ls.builtins.formatting.stylua.with({
            filetypes = { 'lua' },
            extra_args = {
              '--indent-type',
              'Spaces',
              '--indent-width',
              '2',
              '--quote-style',
              'AutoPreferSingle',
            },
          }),
          null_ls.builtins.formatting.goimports,
          null_ls.builtins.formatting.prettier.with({
            filetypes = { 'typescriptreact', 'typescript', 'javascript', 'json', 'yaml' },
            extra_args = { '--write' }, -- 保存時に自動修正
          }),
          null_ls.builtins.formatting.shfmt,
          null_ls.builtins.formatting.terraform_fmt,

          -- リンター
          null_ls.builtins.diagnostics.golangci_lint,
          null_ls.builtins.diagnostics.yamllint,
          require('none-ls.diagnostics.eslint').with({
            condition = function(utils)
              return utils.root_has_file({ '.eslintrc.js', '.eslintrc.cjs', '.eslintrc.json' })
            end,
          }),
        },
        on_attach = function(client, bufnr)
          -- If a null_ls formatter is available, it takes precedence over LSP.
          if client.supports_method('textDocument/formatting') == true then
            vim.api.nvim_clear_autocmds({ group = formatgroup, buffer = bufnr })
            vim.api.nvim_create_autocmd('BufWritePre', {
              group = formatgroup,
              buffer = bufnr,
              callback = function()
                null_ls_formatting(bufnr)
              end,
            })
          end
        end,
      })
    end,
  },
  {
    'hrsh7th/nvim-cmp',
    event = { 'InsertEnter', 'CmdlineEnter' },
    dependencies = {
      { 'hrsh7th/cmp-nvim-lsp' },
      { 'hrsh7th/cmp-nvim-lua' },
      { 'hrsh7th/cmp-nvim-lsp-signature-help' },
      { 'lukas-reineke/cmp-rg' },
      {
        'uga-rosa/cmp-skkeleton',
        dependencies = {
          { 'vim-skk/skkeleton' },
        },
      },
      { 'hrsh7th/cmp-buffer' },
      { 'hrsh7th/cmp-path' },
      { 'hrsh7th/cmp-cmdline' },
      { 'hrsh7th/cmp-emoji' },
      { 'hrsh7th/cmp-vsnip' },
      { 'onsails/lspkind.nvim' },
      { 'nvim-tree/nvim-web-devicons' },
      { 'hrsh7th/vim-vsnip' }, -- Snippet engine
      {
        'zbirenbaum/copilot-cmp',
        dependencies = {
          { 'zbirenbaum/copilot.lua' },
        },
      },
    },
    config = function()
      local cmp = require('cmp')
      local lspkind = require('lspkind')

      require('copilot_cmp').setup()

      local sources = {
        { name = 'copilot' },
        { name = 'skkeleton' },
        { name = 'nvim_lsp' },
        { name = 'nvim_lua', max_item_count = 20 },
        { name = 'nvim_lsp_signature_help' },
        { name = 'buffer' },
        { name = 'rg', keyword_length = 4, max_item_count = 10 },
        { name = 'path' },
        { name = 'vsnip' },
        { name = 'emoji' },
        { name = 'cmdline' },
      }

      cmp.setup({
        window = {
          completion = cmp.config.window.bordered({}),
          documentation = cmp.config.window.bordered({}),
        },
        snippet = {
          expand = function(args)
            vim.fn['vsnip#anonymous'](args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<C-e>'] = cmp.mapping.abort(),
          ['<CR>'] = cmp.mapping(function(fallback)
            if cmp.visible() and cmp.get_selected_entry() then
              cmp.confirm({ select = true })
            else
              fallback()
            end
          end),
          ['<C-n>'] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item({ behavior = cmp.SelectBehavior.Insert })
            else
              fallback()
            end
          end, { 'i', 's' }),
          ['<C-p>'] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item({ behavior = cmp.SelectBehavior.Insert })
            else
              fallback()
            end
          end, { 'i', 's' }),
          ['<Tab>'] = cmp.mapping(function(fallback)
            if vim.fn == 1 then
              vim.fn.feedkeys(vim.api.nvim_replace_termcodes('<Plug>(vsnip-expand-or-jump)', true, true, true), '')
            elseif cmp.visible() then
              cmp.select_next_item({ behavior = cmp.SelectBehavior.Insert })
            else
              fallback()
            end
          end, { 'i', 's' }),
          ['<S-Tab>'] = cmp.mapping(function(fallback)
            if vim.fn['vsnip#jumpable'](-1) == 1 then
              vim.fn.feedkeys(vim.api.nvim_replace_termcodes('<Plug>(vsnip-jump-prev)', true, true, true), '')
            elseif cmp.visible() then
              cmp.select_prev_item({ behavior = cmp.SelectBehavior.Insert })
            else
              fallback()
            end
          end, { 'i', 's' }),
        }),
        sources = cmp.config.sources(sources),
        formatting = {
          expandable_indicator = true,
          fields = { 'kind', 'abbr', 'menu' },
          format = lspkind.cmp_format({
            mode = 'symbol',
            maxwidth = 50,
            ellipsis_char = '...',
            before = function(entry, vim_item)
              vim_item.menu = ({
                copilot = ' ',
                nvim_lsp = '[LSP]',
                vsnip = '[Snippet]',
                buffer = '[Buffer]',
                nvim_lsp_signature_help = '[Signature]',
                rg = '[Rg]',
                path = '[Path]',
                skkeleton = '[Skel]',
                emoji = '[Emoji]',
                cmdline = '[Cmd]',
              })[entry.source.name] or entry.source.name
              return vim_item
            end,
          }),
        },
      })

      local cmdline_mappings = cmp.mapping.preset.cmdline({
        ['<C-n>'] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Insert }),
        ['<C-p>'] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Insert }),
        ['<C-e>'] = cmp.mapping.close(),
      })

      local incsearch_settings = {
        mapping = cmdline_mappings,
        sources = cmp.config.sources({
          { name = 'buffer' },
        }),
        formatting = {
          fields = { 'kind', 'abbr' },
          format = lspkind.cmp_format({ mode = 'symbol' }),
        },
      }

      cmp.setup.cmdline('/', incsearch_settings)
      cmp.setup.cmdline('?', incsearch_settings)
      cmp.setup.cmdline(':', {
        mapping = cmdline_mappings,
        sources = cmp.config.sources({
          { name = 'cmdline' },
          { name = 'path' },
        }),
        formatting = {
          expandable_indicator = true,
          fields = { 'kind', 'abbr', 'menu' },
          format = function(entry, vim_item)
            if vim.tbl_contains({ 'path', 'fuzzy_path' }, entry.source.name) then
              local icon, hl_group = require('nvim-web-devicons').get_icon(entry.completion_item.label)
              if icon then
                vim_item.kind = icon
                vim_item.kind_hl_group = hl_group
              else
                vim_item.kind = misc_icons.file
              end
            elseif 'cmdline' == entry.source.name then
              vim_item.kind = misc_icons.cmd
              vim_item.dup = 1
            end

            return lspkind.cmp_format()(entry, vim_item)
          end,
        },
      })

      -- Insert '(' after confirming a function or method
      cmp.event:on('confirm_done', function(evt)
        local kind = evt.entry:get_kind()
        if kind == cmp.lsp.CompletionItemKind.Function or kind == cmp.lsp.CompletionItemKind.Method then
          vim.api.nvim_feedkeys('(', 'n', true)
        end
      end)
    end,
  },
  {
    'cohama/lexima.vim',
    event = 'InsertEnter', -- 挿入モードで自動的に読み込む
    config = function()
      -- Ctrl-h を Backspace として動作させる設定
      vim.g.lexima_ctrlh_as_backspace = 4

      -- デフォルトの補完ルールを無効化
      vim.g.lexima_no_default_rules = true

      -- デフォルトの補完ルールを設定
      vim.cmd([[
        call lexima#set_default_rules()
      ]])
    end,
  },
}
