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
      local function exec_git_command(cwd, cmd)
        local full_cmd = string.format('cd %q && %s', cwd, cmd)
        local output = vim.fn.systemlist(full_cmd)
        if vim.v.shell_error ~= 0 or not output or #output == 0 then
          return nil
        end
        return table.concat(output, '\n')
      end

      local function get_default_branch(cwd)
        local output = exec_git_command(cwd, 'git symbolic-ref refs/remotes/origin/HEAD')
        if not output then
          return 'main'
        end
        local branch = output:match('refs/remotes/origin/(%S+)') or 'main'
        return branch
      end

      -- 差分を解析する関数
      local function parse_diff(diff_output)
        local diff_lines = {}
        local current_old_line, current_new_line

        for line in diff_output:gmatch('[^\r\n]+') do
          local old_line_start, _, new_line_start, _ = line:match('^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@')
          if old_line_start and new_line_start then
            table.insert(diff_lines, line)
            current_old_line = tonumber(old_line_start)
            current_new_line = tonumber(new_line_start)
          elseif line:sub(1, 1) == '-' and current_old_line then
            table.insert(diff_lines, string.format('%d: %s', current_old_line, line))
            current_old_line = current_old_line + 1
          elseif line:sub(1, 1) == '+' and current_new_line then
            table.insert(diff_lines, string.format('%d: %s', current_new_line, line))
            current_new_line = current_new_line + 1
          else
            if current_old_line and current_new_line then
              table.insert(diff_lines, string.format('   %s', line))
              current_old_line = current_old_line + 1
              current_new_line = current_new_line + 1
            end
          end
        end

        return table.concat(diff_lines, '\n')
      end

      -- レビューのレスポンスから診断情報を生成する関数
      local function parse_review_response(response, ns, bufnr)
        local diagnostics = {}
        local stats = { error = 0, warn = 0, info = 0, hint = 0 }

        for line in response:gmatch('[^\r\n]+') do
          if line:find('^line=') then
            local start_line, end_line, message
            -- まずはシングル行パターン
            local single_start, single_message = line:match('^line=(%d+): (.*)$')
            if single_start then
              start_line = tonumber(single_start)
              end_line = start_line
              message = single_message
            else
              -- 複数行にまたがるパターン
              local range_start, range_end, range_message = line:match('^line=(%d+)-(%d+): (.*)$')
              if range_start and range_end then
                start_line = tonumber(range_start)
                end_line = tonumber(range_end)
                message = range_message
              end
            end

            if start_line and end_line and message then
              local severity = vim.diagnostic.severity.INFO
              local lower_msg = message:lower()
              if lower_msg:match('critical') or lower_msg:match('error') then
                severity = vim.diagnostic.severity.ERROR
                stats.error = stats.error + 1
              elseif lower_msg:match('warning') or lower_msg:match('warn') then
                severity = vim.diagnostic.severity.WARN
                stats.warn = stats.warn + 1
              elseif lower_msg:match('style') or lower_msg:match('suggestion') then
                severity = vim.diagnostic.severity.HINT
                stats.hint = stats.hint + 1
              else
                stats.info = stats.info + 1
              end

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

        vim.diagnostic.set(ns, bufnr, diagnostics)
        return stats
      end

      -- カスタムコンテキストの定義
      local contexts = {
        git_diff = {
          resolve = function(input, source)
            local utils = require('CopilotChat.utils')
            local cwd = utils.win_cwd(source.winnr)
            if not cwd or cwd == '' then
              return nil
            end

            local default_branch = get_default_branch(cwd)
            if not default_branch or default_branch == '' then
              return nil
            end

            local diff_output = exec_git_command(cwd, 'git diff --no-color --no-ext-diff --staged')
            if not diff_output or diff_output == '' then
              diff_output =
                exec_git_command(cwd, string.format('git diff --no-color --no-ext-diff %s...HEAD', default_branch))
              if not diff_output or diff_output == '' then
                return nil
              end
            end

            local parsed_diff = parse_diff(diff_output)
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
        Explain = {
          prompt = '/COPILOT_EXPLAIN このコードの説明を段落のテキストとして書いてください。',
          selection = select.visual,
        },
        Review = {
          selection = select.buffer,
          prompt = '> #git_diff\n\n>#files\n\n>#buffer\n\nこのコードの変更をレビューしてください。',
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

重要度に応じて以下のキーワードを含めてください：
- 重大な問題: "error:" または "critical:"
- 警告: "warning:"
- スタイル的な提案: "style:"
- その他の提案: "suggestion:"
]],
          callback = function(response, source)
            local ns = vim.api.nvim_create_namespace('copilot_review')
            vim.diagnostic.reset(ns)

            if not response or response == '' then
              vim.notify('レビュー結果が空です', vim.log.levels.WARN)
              return
            end

            local stats = parse_review_response(response, ns, source.bufnr)
            vim.schedule(function()
              local summary = string.format(
                'コードレビュー完了:\n- エラー: %d\n- 警告: %d\n- 情報: %d\n- ヒント: %d',
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
        model = 'claude-3.5-sonnet',
        chat_autocomplete = true,
        auto_insert_mode = false,
        auto_follow_cursor = true,
        clear_chat_on_new_prompt = false,
        show_help = true,
        question_header = '  ' .. (vim.env.USER or 'User') .. ' ',
        answer_header = '  Copilot ',
        window = {
          width = 0.5,
        },
        selection = function(source)
          return select.visual(source) or select.buffer(source)
        end,
        mappings = {
          submit_prompt = {
            normal = '<CR>',
            insert = '<C-k>',
          },
        },
        system_prompt = 'Your name is Github Copilot and you are a AI assistant for developers. response language is Japanese.',
        prompts = prompts,
        contexts = contexts,
      }

      local chat = require('CopilotChat')
      chat.setup(opts)

      vim.api.nvim_create_user_command('CopilotChatVisual', function(args)
        chat.ask(args.args, { selection = select.visual })
      end, { nargs = '*', range = true })

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

      vim.api.nvim_create_autocmd('BufEnter', {
        pattern = 'copilot-chat',
        callback = function()
          vim.opt_local.relativenumber = false
          vim.opt_local.number = false
        end,
      })

      local keymap = vim.keymap.set
      keymap({ 'n', 'v' }, '<leader>cs', function()
        local input = vim.fn.input('Perplexity: ')
        if input ~= '' then
          require('CopilotChat').ask('Please respond in Japanese. ' .. input, {
            agent = 'perplexityai',
            selection = false,
          })
        end
      end, { desc = 'CopilotChat - Perplexity Search' })

      keymap('n', '<leader>co', '<cmd>CopilotChatOpen<cr>', { desc = 'Open' })
      keymap('n', '<leader>cc', '<cmd>CopilotChatClose<cr>', { desc = 'Close' })
      keymap('n', '<leader>ct', '<cmd>CopilotChatToggle<cr>', { desc = 'Toggle' })
      keymap('n', '<leader>cf', '<cmd>CopilotChatFixDiagnostic<cr>', { desc = 'Fix Diagnostic' })
      keymap('n', '<leader>cr', '<cmd>CopilotChatReview<cr>', { desc = 'Review' })
      keymap('n', '<leader>cD', '<cmd>CopilotChatDebugInfo<cr>', { desc = 'Debug info' })

      keymap('n', '<leader>chh', function()
        local actions = require('CopilotChat.actions')
        require('CopilotChat.integrations.telescope').pick(actions.help_actions())
      end, { desc = 'Help actions' })

      keymap('n', '<leader>cp', function()
        local actions = require('CopilotChat.actions')
        require('CopilotChat.integrations.telescope').pick(actions.prompt_actions(), {
          layout_strategy = 'horizontal',
          layout_config = {
            width = 0.8,
            height = 0.6,
            preview_width = 0.5,
          },
        })
      end, { desc = 'Prompt actions (Normal)' })

      keymap(
        'x',
        '<leader>cp',
        ":lua require('CopilotChat.integrations.telescope').pick(require('CopilotChat.actions').prompt_actions({selection = require('CopilotChat.select').visual}))<CR>",
        { desc = 'Prompt actions (Visual)' }
      )
      keymap(
        'n',
        '<leader>cm',
        '<cmd>CopilotChatCommitStaged<cr>',
        { desc = 'Generate commit message for staged changes' }
      )

      keymap('n', '<leader>ci', function()
        local input = vim.fn.input('Ask Copilot: ')
        if input ~= '' then
          vim.cmd('CopilotChat ' .. input)
        end
      end, { desc = 'Ask input (Normal)' })

      keymap('x', '<leader>ci', ':CopilotChatInline<cr>', { desc = 'Inline chat (Visual)' })

      keymap('n', '<leader>cq', function()
        local input = vim.fn.input('Quick Chat: ')
        if input ~= '' then
          require('CopilotChat').ask(input, { selection = require('CopilotChat.select').buffer })
        end
      end, { desc = 'Quick chat' })
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
      'CopilotChatCommit',
      'CopilotChatCommitStaged',
      'CopilotChatDocs',
      'CopilotChatExplain',
      'CopilotChatFix',
      'CopilotChatFixDiagnostic',
      'CopilotChatOptimize',
      'CopilotChatReview',
      'CopilotChatTests',
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
      { '<leader>co', '<cmd>CopilotChatOpen<cr>', desc = 'Open', mode = 'n' },
      { '<leader>cc', '<cmd>CopilotChatClose<cr>', desc = 'Close', mode = 'n' },
      { '<leader>ct', '<cmd>CopilotChatToggle<cr>', desc = 'Toggle', mode = 'n' },
      { '<leader>cf', '<cmd>CopilotChatFixDiagnostic<cr>', desc = 'Fix Diagnostic', mode = 'n' },
      { '<leader>cr', '<cmd>CopilotChatReview<cr>', desc = 'Review', mode = 'n' },
      { '<leader>cD', '<cmd>CopilotChatDebugInfo<cr>', desc = 'Debug info', mode = 'n' },
      {
        '<leader>chh',
        function()
          local actions = require('CopilotChat.actions')
          require('CopilotChat.integrations.telescope').pick(actions.help_actions())
        end,
        desc = 'Help actions',
        mode = 'n',
      },
      {
        '<leader>cp',
        function()
          local actions = require('CopilotChat.actions')
          require('CopilotChat.integrations.telescope').pick(actions.prompt_actions(), {
            layout_strategy = 'horizontal',
            layout_config = {
              width = 0.8,
              height = 0.6,
              preview_width = 0.5,
            },
          })
        end,
        desc = 'Prompt actions (Normal)',
        mode = 'n',
      },
      {
        '<leader>cp',
        ":lua require('CopilotChat.integrations.telescope').pick(require('CopilotChat.actions').prompt_actions({selection = require('CopilotChat.select').visual}))<CR>",
        desc = 'Prompt actions (Visual)',
        mode = 'x',
      },
      {
        '<leader>cm',
        '<cmd>CopilotChatCommitStaged<cr>',
        desc = 'Generate commit message for staged changes',
        mode = 'n',
      },
      {
        '<leader>ci',
        function()
          local input = vim.fn.input('Ask Copilot: ')
          if input ~= '' then
            vim.cmd('CopilotChat ' .. input)
          end
        end,
        desc = 'Ask input (Normal)',
        mode = 'n',
      },
      { '<leader>ci', ':CopilotChatInline<cr>', desc = 'Inline chat (Visual)', mode = 'x' },
      {
        '<leader>cq',
        function()
          local input = vim.fn.input('Quick Chat: ')
          if input ~= '' then
            require('CopilotChat').ask(input, { selection = require('CopilotChat.select').buffer })
          end
        end,
        desc = 'Quick chat',
        mode = 'n',
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
        ['Code workflow'] = {
          strategy = 'workflow',
          description = 'Use a workflow to guide an LLM in writing code',
          opts = {
            index = 4,
            short_name = 'workflow',
          },
          prompts = {
            {
              -- We can group prompts together to make a workflow
              -- This is the first prompt in the workflow
              {
                role = 'system',
                content = function(context)
                  return string.format(
                    "You carefully provide accurate, factual, thoughtful, nuanced answers, and are brilliant at reasoning. If you think there might not be a correct answer, you say so. Always spend a few sentences explaining background context, assumptions, and step-by-step thinking BEFORE you try to answer a question. Don't be verbose in your answers, but do provide details and examples where it might help the explanation. You are an expert software engineer for the %s language",
                    context.filetype
                  )
                end,
                opts = {
                  visible = false,
                },
              },
              {
                role = 'user',
                content = 'I want you to ',
                opts = {
                  auto_submit = false,
                },
              },
            },
            -- This is the second group of prompts
            {
              {
                role = 'user',
                content = "Great. Now let's consider your code. I'd like you to check it carefully for correctness, style, and efficiency, and give constructive criticism for how to improve it.",
                opts = {
                  auto_submit = true,
                },
              },
            },
            -- This is the final group of prompts
            {
              {
                role = 'user',
                content = "Thanks. Now let's revise the code based on the feedback, without additional explanations.",
                opts = {
                  auto_submit = true,
                },
              },
            },
          },
        },
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
