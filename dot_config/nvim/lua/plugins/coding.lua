local misc_icons = require('rc.font').misc_icons

local function is_null_ls_formatter_available(bufnr)
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  for _, client in ipairs(clients) do
    if client.name == 'null-ls' and client.supports_method('textDocument/formatting') then
      return true
    end
  end
  return false
end
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
return {
  -- Lua開発を強化するLazydevプラグイン (neodevの後継)
  {
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
      },
    },
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
      { 'folke/lazydev.nvim' },
      { 'b0o/schemastore.nvim' },
      { 'hrsh7th/cmp-nvim-lsp' },
      { 'j-hui/fidget.nvim' },
      { 'folke/trouble.nvim' },
    },
    config = function()

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

      -- 診断メッセージの表示設定を改善
      vim.diagnostic.config({
        virtual_text = {
          -- 各診断メッセージのソース（linter名）を表示する
          format = function(diagnostic)
            -- diagnostic.source は linter や LSP サーバーの名前
            if diagnostic.source then
              return string.format('[%s] %s', diagnostic.source, diagnostic.message)
            else
              return diagnostic.message
            end
          end,
        },
        float = {
          -- フロートウィンドウのボーダーを設定
          border = 'rounded',
          focusable = false,
          style = 'minimal',
          format = function(diag)
            if diag.code then
              return string.format('[%s](%s): %s', diag.source, diag.code, diag.message)
            else
              return string.format('[%s]: %s', diag.source, diag.message)
            end
          end,
        },
        signs = true,
        underline = true,
        severity_sort = true, -- 診断の重大度でソート
      })
      vim.keymap.set('n', '<leader>e', function()
        vim.diagnostic.open_float(nil, { focusable = false, border = 'rounded' })
      end, { noremap = true, silent = true })

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
      -- Neovim 0.11+ のデフォルトキーマップ:
      -- grn: rename, gra: code_action, grr: references, gri: implementation
      -- gO: document_symbol, K: hover, CTRL-S (insert): signature_help
      local on_attach = function(client, bufnr)
        if client.name == 'ts_ls' then
          client.server_capabilities.documentFormattingProvider = false
          client.server_capabilities.documentRangeFormattingProvider = false
        end
        local bufopts = { noremap = true, silent = true, buffer = bufnr }
        -- カスタムキーマップ (デフォルトを補完)
        vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bufopts)
        vim.keymap.set('n', 'gD', vim.lsp.buf.references, bufopts)
        vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, bufopts)
        vim.keymap.set('n', ']d', vim.diagnostic.goto_next, bufopts)

        if is_null_ls_formatter_available(bufnr) then
          vim.keymap.set(
            'n',
            ',f',
            null_ls_formatting,
            { replace_keycodes = false, noremap = true, silent = true, buffer = bufnr }
          )
        else
          vim.keymap.set('n', ',f', vim.lsp.buf.format, bufopts)
        end

        -- LSP診断メッセージをヤンクする設定
        vim.keymap.set('n', '<leader>yd', function()
          local diagnostics = vim.diagnostic.get(0, { lnum = vim.fn.line('.') - 1 })
          if #diagnostics > 0 then
            local diagnostic = diagnostics[1]
            local formatted_message
            if diagnostic.source then
              -- ソース名とメッセージを組み合わせてフォーマットする
              formatted_message = string.format('[%s] %s', diagnostic.source, diagnostic.message)
            else
              formatted_message = diagnostic.message
            end
            -- フォーマットしたメッセージをクリップボードにコピー
            vim.fn.setreg('+', formatted_message)
          end
        end, bufopts)
      end

      -- LSPサーバー設定 (Neovim 0.11+ vim.lsp.config/enable API)
      local servers = {
        lua_ls = {
          settings = {
            Lua = {
              runtime = { version = 'LuaJIT' },
              diagnostics = { globals = { 'vim' } },
              workspace = { checkThirdParty = false },
              telemetry = { enable = false },
            },
          },
        },
        gopls = {
          settings = {
            gopls = {
              usePlaceholders = true,
              completeUnimported = true,
              staticcheck = true,
              analyses = { unusedparams = true, unreachable = true },
            },
          },
        },
        yamlls = {
          settings = {
            yaml = {
              keyOrdering = false,
              schemas = require('schemastore').yaml.schemas(),
            },
          },
        },
        pyright = {
          settings = {
            python = {
              analysis = {
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                diagnosticMode = 'workspace',
                typeCheckingMode = 'off',
              },
            },
          },
        },
        ts_ls = {},
        bashls = {},
        terraformls = {},
        typos_lsp = {},
        prismals = {},
        graphql = {},
      }

      -- 共通設定を適用してLSPを有効化
      for name, config in pairs(servers) do
        config.on_attach = on_attach
        config.capabilities = capabilities
        config.handlers = handlers
        vim.lsp.config(name, config)
        vim.lsp.enable(name)
      end

      -- Mason setup
      require('mason').setup()

      -- Mason-lspconfig setup (Neovim 0.11+: automatic_enable がデフォルトで有効)
      require('mason-lspconfig').setup({
        ensure_installed = vim.tbl_keys(servers),
      })
    end,
  },
  -- MasonによるLSPサーバー管理
  {
    'williamboman/mason.nvim',
    build = ':MasonUpdate',
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
          null_ls.builtins.formatting.terraform_fmt.with({
            filetypes = { 'hcl', 'tf', 'tfvars' },
          }),

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
      {
        'biosugar0/cmp-claudecode',
        opts = {
          enabled = {
            custom = function()
              return vim.env.EDITPROMPT == '1'
            end,
          },
        },
      },
      { 'onsails/lspkind.nvim' },
      { 'nvim-tree/nvim-web-devicons' },
      { 'hrsh7th/vim-vsnip' }, -- Snippet engine
    },
    config = function()
      local cmp = require('cmp')
      local lspkind = require('lspkind')

      local sources = {
        { name = 'claude_slash', priority = 900 },
        { name = 'claude_at', priority = 900 },
        { name = 'lazydev', group_index = 0 }, -- lazydev を優先 (Lua)
        { name = 'skkeleton' },
        { name = 'nvim_lsp' },
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
                lazydev = '[LazyDev]',
                skkeleton = '[Skel]',
                nvim_lsp = '[LSP]',
                vsnip = '[Snippet]',
                buffer = '[Buffer]',
                nvim_lsp_signature_help = '[Signature]',
                rg = '[Rg]',
                path = '[Path]',
                emoji = '[Emoji]',
                cmdline = '[Cmd]',
                claude_slash = '[Claude /]',
                claude_at = '[Claude @]',
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
