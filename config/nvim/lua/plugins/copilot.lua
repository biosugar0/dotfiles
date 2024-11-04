return {
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    event = 'InsertEnter',
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

      -- 自動サインイン
      require('copilot.auth').signin()
    end,
  },
  {
    'CopilotC-Nvim/CopilotChat.nvim',
    branch = 'canary',
    dependencies = {
      { 'zbirenbaum/copilot.lua' }, -- Copilotのコアモジュール
      { 'nvim-lua/plenary.nvim' }, -- Neovimのユーティリティ関数を提供
      { 'rcarriga/nvim-notify' },
    },
    build = 'make tiktoken', -- MacOSやLinux向けビルド
    config = function()
      -- デフォルトブランチ名を動的に取得する関数
      local function get_default_branch()
        local handle = io.popen('git symbolic-ref refs/remotes/origin/HEAD 2> /dev/null')
        if not handle then
          return nil
        end
        local result = handle:read('*a')
        handle:close()

        -- リモートHEADの参照結果からブランチ名を抽出
        if result and result ~= '' then
          local branch = result:match('refs/remotes/origin/(%S+)')
          return branch or 'main' -- フォールバックは 'main'
        else
          return 'main' -- フォールバックとして 'main' を返す
        end
      end
      -- 差分を解析する関数
      local function parse_diff(diff_output)
        local diff_lines = {}
        local current_old_line, current_new_line

        -- 各行を解析
        for line in diff_output:gmatch('[^\r\n]+') do
          -- diffブロックの行番号を解析 (例: @@ -21,6 +21,7 @@)
          local old_line_start, old_line_count, new_line_start, new_line_count =
            line:match('^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@')

          if old_line_start and new_line_start then
            -- 行番号が見つかった場合
            table.insert(diff_lines, line)
            -- 行番号の初期化
            current_old_line = tonumber(old_line_start)
            current_new_line = tonumber(new_line_start)
          elseif line:sub(1, 1) == '-' and current_old_line then
            -- 変更前の行（`-`で始まる）
            table.insert(diff_lines, string.format('%d: %s', current_old_line, line))
            current_old_line = current_old_line + 1
          elseif line:sub(1, 1) == '+' and current_new_line then
            -- 変更後の行（`+`で始まる）
            table.insert(diff_lines, string.format('%d: %s', current_new_line, line))
            current_new_line = current_new_line + 1
          else
            -- コンテキスト行（変更なし）で行番号がnilでない場合
            if current_old_line and current_new_line then
              table.insert(diff_lines, string.format('   %s', line))
              current_old_line = current_old_line + 1
              current_new_line = current_new_line + 1
            end
          end
        end

        -- テーブルの内容を文字列に変換して返す
        return table.concat(diff_lines, '\n')
      end

      -- diffの出力を取得する関数
      local function gitdiff(select, source, staged)
        local select_buffer = select.buffer(source)
        if not select_buffer then
          return nil
        end

        local bufname = vim.api.nvim_buf_get_name(source.bufnr)
        local file_path = bufname:gsub('^%w+://', '')
        local dir = vim.fn.fnamemodify(file_path, ':h')
        if not dir or dir == '' then
          return nil
        end
        dir = dir:gsub('.git$', '')

        local default_branch = get_default_branch()
        local cmd
        if staged then
          cmd = 'git -C ' .. dir .. ' diff --no-color --no-ext-diff --cached'
        else
          cmd = 'git -C ' .. dir .. ' diff --no-color --no-ext-diff ' .. default_branch .. '...HEAD'
        end

        local handle = io.popen(cmd)
        if not handle then
          return nil
        end

        local result = handle:read('*a')
        handle:close()
        if not result or result == '' then
          return nil
        end

        select_buffer.filetype = 'diff'
        select_buffer.lines = parse_diff(result) -- 構造化したdiffをlinesに格納
        return select_buffer
      end

      local select = require('CopilotChat.select')
      local prompts = {
        -- コード関連のプロンプト
        Explain = {
          prompt = '/COPILOT_EXPLAIN このコードの説明を段落のテキストとして書いてください。',
          selection = select.visual,
        },
        Review = {
          prompt = [[
与えられたコードのdiffをレビューし、特に読みやすさと保守性に焦点を当ててください。
以下に関連する問題を特定してください：
- 名前付け規則が不明確、誤解を招く、または使用されている言語の規則に従っていない場合。
- 不要なコメントの有無、または必要なコメントが不足している場合。
- 複雑すぎる表現があり、簡素化が望ましい場合。
- ネストのレベルが高く、コードが追いづらい場合。
- 変数や関数に対して名前が過剰に長い場合。
- 命名、フォーマット、または全体的なコーディングスタイルに一貫性が欠けている場合。
- 抽象化や最適化によって効率的に処理できる繰り返しのコードパターンがある場合。

フィードバックは簡潔に行い、各特定された問題について次の要素を直接示してください：
- 問題が見つかった具体的な行番号
- 問題の明確な説明
- 改善または修正方法に関する具体的な提案

フィードバックの形式は次のようにしてください：
line=<行番号>: <問題の説明>

問題が複数行にわたる場合は、次の形式を使用してください：
line=<開始行>-<終了行>: <問題の説明>

同じ行に複数の問題がある場合は、それぞれの問題を同じフィードバック内でセミコロンで区切って記載してください。
指摘が複数にわたる場合は、一行にまとめるように文字列を整形してください。

フィードバック例：
line=3: 変数名「x」が不明瞭です。変数宣言の横にあるコメントは不要です。
line=8: 式が複雑すぎます。式をより簡単な要素に分解してください。
line=10: この部分でのキャメルケースの使用はLuaの慣例に反します。スネークケースを使用してください。
line=11-15: ネストが過剰で、コードの追跡が困難です。\nネストレベルを減らすためにリファクタリングを検討してください。

コードスニペットに読みやすさの問題がない場合、その旨を簡潔に記し、コードが明確で十分に書かれていることを確認してください。

diffの出力には、変更された行やその位置を示す情報が含まれています。この情報を用いて、**変更後のコードの正確な行番号**を特定し、その行番号に基づいて指摘を行ってください。

重要度に応じて以下のキーワードを含めてください：
- 重大な問題: "error:" または "critical:"
- 警告: "warning:"
- スタイル的な提案: "style:"
- その他の提案: "suggestion:"
]],
          selection = function(source)
            -- バッファのファイルパスを取得
            local bufnr = source.bufnr
            local selection_table = gitdiff(select, source, false)
            -- selection_tableがnilじゃなかったらfile_path だけのdiffを使うようにする
            if selection_table then
              local file_path = vim.api.nvim_buf_get_name(bufnr)
              selection_table.prompt_extra = '\n与えられたdiffのうち、'
                .. file_path
                .. ' の変更に対してレビューを行ってください。'
            end
            return selection_table
          end,
          callback = function(response, source)
            -- 名前空間の作成とクリーンアップ
            local ns = vim.api.nvim_create_namespace('copilot_review')
            vim.diagnostic.reset(ns)

            -- レスポンスの検証
            if not response or response == '' then
              vim.notify('レビュー結果が空です', vim.log.levels.WARN)
              return
            end

            -- 診断情報の初期化
            local diagnostics = {}
            local stats = { error = 0, warn = 0, info = 0, hint = 0 }

            -- レスポンスの解析と診断情報の生成
            for line in response:gmatch('[^\r\n]+') do
              if line:find('^line=') then
                local start_line, end_line, message = nil, nil, nil
                local single_match, message_match = line:match('^line=(%d+): (.*)$')

                if not single_match then
                  local start_match, end_match, m_message_match = line:match('^line=(%d+)-(%d+): (.*)$')
                  if start_match and end_match then
                    start_line = tonumber(start_match)
                    end_line = tonumber(end_match)
                    message = m_message_match
                  end
                else
                  start_line = tonumber(single_match)
                  end_line = start_line
                  message = message_match
                end

                if start_line and end_line and message then
                  -- 重要度の判定
                  local severity = vim.diagnostic.severity.INFO
                  if message:lower():match('critical') or message:lower():match('error') then
                    severity = vim.diagnostic.severity.ERROR
                    stats.error = stats.error + 1
                  elseif message:lower():match('warning') or message:lower():match('warn') then
                    severity = vim.diagnostic.severity.WARN
                    stats.warn = stats.warn + 1
                  elseif message:lower():match('style') or message:lower():match('suggestion') then
                    severity = vim.diagnostic.severity.HINT
                    stats.hint = stats.hint + 1
                  else
                    stats.info = stats.info + 1
                  end

                  -- 診断情報の追加
                  table.insert(diagnostics, {
                    lnum = start_line - 1,
                    end_lnum = end_line - 1,
                    col = 0,
                    end_col = 0,
                    message = message,
                    severity = severity,
                    source = 'Copilot Review',
                  })
                end
              end
            end

            -- 診断情報の設定
            vim.diagnostic.set(ns, source.bufnr, diagnostics)

            -- レビュー結果のサマリー通知
            vim.schedule(function()
              local summary = string.format(
                'コードレビュー完了:\n'
                  .. '- エラー: %d\n'
                  .. '- 警告: %d\n'
                  .. '- 情報: %d\n'
                  .. '- ヒント: %d',
                stats.error,
                stats.warn,
                stats.info,
                stats.hint
              )
              vim.notify(summary, vim.log.levels.INFO, {
                title = 'Copilot Review',
                timeout = 5000,
              })
            end)
          end,
        },
        Fix = {
          prompt = '/COPILOT_GENERATE このコードには問題があります。問題を解決するためにコードを書き直してください。',
        },
        Tests = {
          prompt = '/COPILOT_GENERATE このコードがどのように動作するか説明し、ユニットテストを生成してください。',
        },
        FixDiagnostic = {
          prompt = 'このファイルの次の診断の問題を解決してください。',
          selection = select.diagnostics,
        },
        CommitStaged = {
          prompt = 'commitizenの規約に従った変更のコミットメッセージを書いてください。タイトルは最大50文字で、メッセージは72文字で折り返します。メッセージ全体をgitcommit言語のコードブロックで囲みます。言語は日本語を使います。',
          selection = function(source)
            return select.gitdiff(source, true)
          end,
        },
      }

      local opts = {
        debug = false, -- デバッグを有効化
        -- Select a model:
        -- 1: gpt-3.5-turbo-0613
        -- 2: gpt-4-0613
        -- 3: gpt-4o-2024-05-13
        -- 4: gpt-4o-2024-08-06
        -- 5: o1-preview-2024-09-12
        -- 6: o1-mini-2024-09-12
        -- 7: gpt-4o-mini-2024-07-18
        -- 8: gpt-4-0125-preview
        -- 9: claude-3.5-sonnet
        model = 'claude-3.5-sonnet',
        auto_insert_mode = false,
        auto_follow_cursor = true, -- 自動的に最新の結果にフォーカス
        clear_chat_on_new_prompt = false, -- 新しいプロンプトでチャットをクリア
        show_help = true,
        question_header = '  ' .. vim.env.USER or 'User' .. ' ',
        answer_header = '  Copilot ',
        window = {
          width = 0.5, -- ウィンドウの幅を50%に拡大
        },
        selection = function(source)
          return select.visual(source) or select.buffer(source)
        end,
        mappings = {
          submit_prompt = {
            -- 通常モードでEnterキーでプロンプトを送信
            normal = '<CR>',
            -- insertモードでCtrl+kでプロンプトを送信
            insert = '<C-k>',
          },
        },
        system_prompt = 'Your name is Github Copilot and you are a AI assistant for developers. response language is Japanese.',
        prompts = prompts,
      }
      -- CopilotChatのセットアップ
      local chat = require('CopilotChat')
      chat.setup(opts)

      -- コマンド作成
      vim.api.nvim_create_user_command('CopilotChatVisual', function(args)
        chat.ask(args.args, { selection = select.visual })
      end, { nargs = '*', range = true })

      -- インラインチャットの設定
      vim.api.nvim_create_user_command('CopilotChatInline', function(args)
        chat.ask(args.args, {
          selection = select.visual,
          window = {
            layout = 'float',
            relative = 'cursor',
            width = 1,
            height = 0.4,
            row = 1,
          },
        })
      end, { nargs = '*', range = true })

      -- cmp統合の設定
      require('CopilotChat.integrations.cmp').setup()

      -- チャットバッファで行番号を非表示
      vim.api.nvim_create_autocmd('BufEnter', {
        pattern = 'copilot-chat',
        callback = function()
          vim.opt_local.relativenumber = false
          vim.opt_local.number = false
        end,
      })
    end,
    cmd = {
      'CopilotChat',
      'CopilotChatClose',
      'CopilotChatDebugInfo',
      'CopilotChatLoad',
      'CopilotChatOpen',
      'CopilotChatReset',
      'CopilotChatSave',
      'CopilotChatToggle',
      'CopilotChatModel',
      'CopilotChatModels',

      -- Default prompts
      'CopilotChatCommit',
      'CopilotChatCommitStaged',
      'CopilotChatDocs',
      'CopilotChatExplain',
      'CopilotChatFix',
      'CopilotChatFixDiagnostic',
      'CopilotChatOptimize',
      'CopilotChatReview',
      'CopilotChatTests',

      -- User commands
      'CopilotChatInline',
      'CopilotChatVisual',
    },
    keys = {
      { '<leader>co', '<cmd>CopilotChatOpen<cr>', desc = 'Open' },
      { '<leader>cc', '<cmd>CopilotChatClose<cr>', desc = 'Close' },
      { '<leader>ct', '<cmd>CopilotChatToggle<cr>', desc = 'Toggle' },
      { '<leader>cf', '<cmd>CopilotChatFixDiagnostic<cr>', desc = 'Fix Diagnostic' },
      {
        '<leader>cr',
        '<cmd>CopilotChatReview<cr>',
        desc = 'Reset',
      },
      {
        '<leader>cD',
        '<cmd>CopilotChatDebugInfo<cr>',
        desc = 'Debug info',
      },
      {
        '<leader>chh',
        function()
          local actions = require('CopilotChat.actions')
          require('CopilotChat.integrations.telescope').pick(actions.help_actions())
        end,
        desc = 'Help actions',
      },
      {
        '<leader>cp',
        function()
          local actions = require('CopilotChat.actions')
          require('CopilotChat.integrations.telescope').pick(actions.prompt_actions(), {
            layout_strategy = 'horizontal', -- horizontalレイアウトを指定
            layout_config = {
              width = 0.8, -- ウィンドウの幅を80%に設定
              height = 0.6, -- 高さを60%に設定
              preview_width = 0.5, -- プレビューウィンドウの幅を50%に設定
            },
          })
        end,
        desc = 'Prompt actions',
      },
      {
        '<leader>cm',
        '<cmd>CopilotChatCommitStaged<cr>',
        desc = 'Generate commit message for staged changes',
      },
      {
        '<leader>ci',
        function()
          local input = vim.fn.input('Ask Copilot: ')
          if input ~= '' then
            vim.cmd('CopilotChat ' .. input)
          end
        end,
        desc = 'Ask input',
      },
      {
        '<leader>cq',
        function()
          local input = vim.fn.input('Quick Chat: ')
          if input ~= '' then
            require('CopilotChat').ask(input, { selection = require('CopilotChat.select').buffer })
          end
        end,
        desc = 'Quick chat',
      },
      {
        '<leader>cp',
        ":lua require('CopilotChat.integrations.telescope').pick(require('CopilotChat.actions').prompt_actions({selection = require('CopilotChat.select').visual}))<CR>",
        mode = 'x',
        desc = 'Prompt actions',
      },
      {
        '<leader>cv',
        ':CopilotChatVisual',
        mode = 'x',
        desc = 'Open in vertical split',
      },
      {
        '<leader>ci',
        ':CopilotChatInline<cr>',
        mode = 'x',
        desc = 'Inline chat',
      },
    },
  },
}
