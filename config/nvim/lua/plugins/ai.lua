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
    branch = 'main',
    dependencies = {
      { 'zbirenbaum/copilot.lua' },
      { 'nvim-lua/plenary.nvim' },
      { 'rcarriga/nvim-notify' },
    },
    build = 'make tiktoken',
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
        local branch = result and result:match('refs/remotes/origin/(%S+)') or 'main'
        return branch
      end

      -- 差分を解析する関数
      local function parse_diff(diff_output)
        local diff_lines = {}
        local current_old_line, current_new_line

        -- 各行を解析
        for line in diff_output:gmatch('[^\r\n]+') do
          -- diffブロックの行番号を解析 (例: @@ -21,6 +21,7 @@)
          local old_line_start, _, new_line_start, _ = line:match('^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@')

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

      -- カスタムコンテキストを定義
      local contexts = {
        git_diff = {
          resolve = function(input, source)
            -- バッファのファイルパスを取得
            local cwd = require('CopilotChat.utils').win_cwd(source.winnr)

            local default_branch = get_default_branch()
            if not default_branch or default_branch == '' then
              -- デフォルトブランチが取得できない場合は終了
              return nil
            end

            -- ステージされた差分を取得
            local cmd_staged = string.format('git -C %s diff --no-color --no-ext-diff --staged', cwd)

            local handle_staged = io.popen(cmd_staged)
            if not handle_staged then
              return nil
            end

            local result_staged = handle_staged:read('*a')
            handle_staged:close()

            local diff_output
            if result_staged and result_staged ~= '' then
              -- ステージされた差分が存在する場合
              diff_output = result_staged
            else
              -- ステージされた差分が空の場合、デフォルトブランチとの差分を取得
              local cmd_default =
                string.format('git -C %s diff --no-color --no-ext-diff %s...HEAD', cwd, default_branch)

              local handle_default = io.popen(cmd_default)
              if not handle_default then
                return nil
              end

              local result_default = handle_default:read('*a')
              handle_default:close()

              if not result_default or result_default == '' then
                -- デフォルトブランチとの差分も存在しない場合
                return nil
              end

              diff_output = result_default
            end

            -- 差分を解析
            local parsed_diff = parse_diff(diff_output)

            -- contextを返す
            return {
              {
                content = parsed_diff,
                filetype = 'diff',
                filename = 'git_diff',
              },
            }
          end,
        },
      }

      local select = require('CopilotChat.select')

      local prompts = {
        -- コード関連のプロンプト
        Explain = {
          prompt = '/COPILOT_EXPLAIN このコードの説明を段落のテキストとして書いてください。',
          selection = select.visual,
        },
        Review = {
          selection = select.buffer,
          prompt = '> #git_diff\n\n> #buffer このコードの変更をレビューしてください。',
          system_prompt = [[
与えられたbufferのコードのdiff内容をレビューし、特に読みやすさと保守性に焦点を当ててください。
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
          prompt = '> #git:staged\n\ncommitizenの規約に従った変更のコミットメッセージを書いてください。タイトルは最大50文字で、メッセージは72文字で折り返します。メッセージ全体をgitcommit言語のコードブロックで囲みます。言語は日本語を使います。',
        },
      }

      local opts = {
        debug = true,
        -- Select a model:
        -- 1: claude-3.5-sonnet
        -- 2: gpt-3.5-turbo
        -- 3: gpt-4
        -- 4: gpt-4-0125-preview
        -- 5: gpt-4o
        -- 6: gpt-4o-2024-08-06
        -- 7: gpt-4o-mini
        -- 8: o1-mini
        -- 9: o1-preview
        model = 'claude-3.5-sonnet',
        chat_autocomplete = true,
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
        contexts = contexts,
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
      {
        '<leader>cs',
        function()
          local input = vim.fn.input('Perplexity: ')
          if input ~= '' then
            require('CopilotChat').ask('Please respond in Japanese. ' .. input, {
              agent = 'perplexityai',
              selection = false,
            })
          end
        end,
        desc = 'CopilotChat - Perplexity Search',
        mode = { 'n', 'v' },
      },
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
            source = diff.gen_source.none(),
          })
        end,
      },
      { 'MeanderingProgrammer/render-markdown.nvim', ft = { 'markdown', 'codecompanion' } },
    },
    keys = {
      { 'cc', 'CodeCompanion', mode = 'ca' },
      { 'ccc', '<cmd>CodeCompanionChat Toggle<cr>', mode = { 'n', 'v' } },
      { 'cca', '<cmd>CodeCompanionActions<cr>', mode = { 'n', 'v' } },
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
          agents = {
            ['my_agent'] = {
              description = 'A custom agent combining tools',
              system_prompt = 'use weather_tool',
              tools = {
                'weather_tool',
              },
            },
            tools = {
              ['weather_tool'] = {
                description = "Get today's Tokyo weather",
                callback = vim.fn.stdpath('config') .. '/lua/plugins/codecompanion/weather_tool.lua',
              },
            },
          },
        },
      },
      display = {
        diff = {
          provider = 'mini_diff', -- mini.diff を使用
        },
        action_palette = {
          provider = 'telescope',
          opts = {
            show_default_actions = true,
          },
          show_default_prompt_library = true,
        },
        chat = {
          show_settings = true,
          show_keys = true,
          show_reference_info = true,
          show_system_messages = true,
        },
      },
      prompt_library = {
        ['Multi Translate'] = {
          strategy = 'chat',
          description = 'Create Translated Text',
          opts = {
            short_name = 'tr',
            auto_submit = true,
            is_slash_cmd = true,
            is_default = true,
            adapter = {
              name = 'copilot',
              model = 'claude-3.5-sonnet',
            },
          },
          prompts = {
            {
              role = 'system',
              content = function(_)
                return [[
You are a bilingual translation expert specialized in Japanese-English translation.
Your primary tasks are:
- Automatically detect the input language
- Translate Japanese to English or other languages to Japanese
- Maintain high accuracy and natural expression in both languages
- Preserve the original tone and context
- Add cultural explanations when necessary
- If the input text is too large, split it into smaller sections and translate each section without omission or summary
                ]]
              end,
            },
            {
              role = 'user',
              content = function(context)
                local text = require('codecompanion.helpers.actions').get_code(context.start_line, context.end_line)
                return 'Please translate the following text:\n```\n' .. text .. '\n```'
              end,
            },
          },
        },
      },
      opts = {
        log_level = 'DEBUG',
        language = 'Japanese',
        send_code = true,
        system_prompt = function(_)
          return [[
あなたは "CodeCompanion" というAIプログラミングアシスタントです。
現在、Neovimのテキストエディタに統合されており、ユーザーがより効率的に作業できるよう支援します。

## あなたの主なタスク:
- 一般的なプログラミングの質問に回答する
- Neovim バッファ内のコードの動作を説明する
- 選択されたコードのレビューを行う
- 選択されたコードの単体テストを生成する
- 問題のあるコードの修正を提案する
- 新しいワークスペース用のコードを作成する
- ユーザーの質問に関連するコードを検索する
- テストの失敗の原因を特定し、修正を提案する
- Neovim に関する質問に答える
- 各種ツールを実行する

## 指示:
- ユーザーの指示を正確に守ること
- 可能な限り簡潔で、要点を押さえた回答を心がけること
- Markdown を使用してフォーマットすること
- コードブロックの最初にプログラミング言語を明示すること
- コードブロック内に行番号を含めないこと
- 回答全体をバッククォートで囲まないこと
- 不要なコードを含めず、タスクに関連するコードのみ返すこと
- 文章中の改行には `\n` を使わず、実際の改行を使用すること
- すべての非コードの応答は日本語で行うこと

## タスクを受けたとき:
1. ステップごとに考え、詳細な擬似コードまたは計画を説明する（特に指定がない限り）
2. コードを1つのコードブロックで出力する（適切な言語名を付与）
3. ユーザーの次のアクションを提案する
4. 各ターンごとに1つの応答のみを返す
          ]]
        end,
      },
    },
    config = function(_, opts)
      require('codecompanion').setup(opts)
    end,
  },
}
