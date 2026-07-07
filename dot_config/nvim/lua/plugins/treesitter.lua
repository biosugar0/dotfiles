return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main', -- Neovim 0.11+ 用のmainブランチ
    build = ':TSUpdate',
    dependencies = {
      { 'JoosepAlviste/nvim-ts-context-commentstring' },
      { 'nvim-treesitter/nvim-treesitter-textobjects', branch = 'main' },
      { 'mfussenegger/nvim-treehopper' },
      { 'bennypowers/nvim-regexplainer' },
      { 'nvim-treesitter/nvim-treesitter-context' },
    },
    config = function()
      -- カスタム言語登録
      vim.treesitter.language.register('json', 'tfstate')
      vim.treesitter.language.register('terraform', 'tf')
      vim.treesitter.language.register('terraform', 'tfvars')
      vim.treesitter.language.register('bash', 'zsh')
      vim.treesitter.language.register('gitcommit', 'gina-commit')

      -- nvim-treesitter setup (mainブランチはシンプル)
      require('nvim-treesitter').setup({})

      -- 必要なパーサーを自動インストール
      local ensure_installed = {
        'vim',
        'toml',
        'python',
        'go',
        'hcl',
        'yaml',
        'bash',
        'sql',
        'json',
        'typescript',
        'tsx',
        'terraform',
        'lua',
        'graphql',
        'gitcommit',
        'markdown',
        'markdown_inline',
        'regex',
      }

      -- パーサーがインストール済みかチェック
      local function is_installed(lang)
        local ok = pcall(vim.treesitter.language.add, lang)
        return ok
      end

      vim.api.nvim_create_autocmd('VimEnter', {
        group = vim.api.nvim_create_augroup('nvim-treesitter-install', { clear = true }),
        once = true,
        callback = function()
          local to_install = vim.tbl_filter(function(lang)
            return not is_installed(lang)
          end, ensure_installed)

          if #to_install > 0 then
            vim.cmd('TSInstall ' .. table.concat(to_install, ' '))
          end
        end,
      })

      -- Treesitterハイライトとインデントの自動有効化
      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('nvim-treesitter-start', { clear = true }),
        callback = function()
          -- パーサーがない場合はエラーを無視
          pcall(vim.treesitter.start)
          -- Treesitterインデントを有効化
          if pcall(vim.treesitter.start) then
            vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })

      require('ts_context_commentstring').setup({
        enable = true,
        enable_autocmd = false,
        config = {
          lua = '-- %s',
          toml = '# %s',
          yaml = '# %s',
        },
      })

      require('treesitter-context').setup()
    end,
  },
  {
    'm-demare/hlargs.nvim',
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    config = function()
      require('hlargs').setup()
    end,
  },
}
