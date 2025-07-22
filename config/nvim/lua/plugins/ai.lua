return {
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    event = 'VeryLazy',
    config = function()
      -- 元の vim.lsp.util.apply_text_edits をラップ
      local original_apply_text_edits = vim.lsp.util.apply_text_edits

      -- 新しい apply_text_edits を定義し、utf-8 に強制する
      vim.lsp.util.apply_text_edits = function(edits, bufnr, encoding)
        -- encoding を utf-8 に強制
        encoding = 'utf-8'
        -- 元の関数を呼び出す
        return original_apply_text_edits(edits, bufnr, encoding)
      end

      -- まずsetupを実行
      require('copilot').setup({
        suggestion = {
          enabled = true,
          auto_trigger = true, -- 自動で提案が表示されるように
          keymap = {
            accept = '<C-l>', -- 提案を受け入れる
            next = '<M-]>', -- 次の提案に移動
            prev = '<M-[>', -- 前の提案に移動
            dismiss = '<C-]>', -- 提案を無視する
          },
        },
        panel = {
          enabled = true, -- 提案パネルを有効化
          auto_refresh = true, -- 自動的に提案を更新
          keymap = {
            open = '<M-p>', -- パネルを開くキー
            accept = '<C-l>', -- 提案を受け入れる
            jump_prev = '[[', -- 前の提案へジャンプ
            jump_next = ']]', -- 次の提案へジャンプ
            refresh = 'gr', -- 提案を手動でリフレッシュ
          },
          layout = {
            position = 'bottom', -- パネルを下に配置
            ratio = 0.3, -- 画面の30%をパネルに割り当てる
          },
        },
        filetypes = {
          yaml = true, -- yamlファイルで有効
          markdown = true, -- markdownファイルで有効
          gitcommit = true, -- gitのコミットメッセージで有効
          python = true, -- pythonファイルで有効
          javascript = true, -- JavaScriptファイルで有効
          lua = true, -- luaファイルで有効
          ['*'] = true, -- 全てのファイルタイプで有効
        },
        copilot_node_command = 'node', -- 使用するNode.jsのパス

        -- LSPサーバーのオプションをオーバーライド
        server_opts_overrides = {},
      })

      -- setupが完了してから自動サインインを実行
      vim.defer_fn(function()
        pcall(function()
          require('copilot.auth').signin()
        end)
      end, 500) -- 500ms遅延
    end,
  },
}
