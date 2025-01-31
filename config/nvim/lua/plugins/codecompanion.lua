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
