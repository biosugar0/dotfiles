local prompts = {
	-- コード関連のプロンプト
	Explain = "次のコードがどのように動作するか説明してください。",
	Review = "次のコードをレビューし、改善の提案をしてください。",
	Tests = "選択されたコードがどのように動作するか説明し、ユニットテストを生成してください。",
	Refactor = "次のコードを、より明確で読みやすいようにリファクタリングしてください。",
	FixCode = "次のコードを修正して、意図通りに動作するようにしてください。",
	FixError = "次のテキストのエラーを説明し、解決策を提供してください。",
	BetterNamings = "次の変数や関数に対して、より適切な名前を提案してください。",
	Documentation = "次のコードのドキュメントを提供してください。",

	-- テキスト関連のプロンプト
	Summarize = "次のテキストを要約してください。",
	Spelling = "次のテキストの文法およびスペルの誤りを修正してください。",
	Wording = "次のテキストの文法と表現を改善してください。",
	Concise = "次のテキストを、より簡潔に書き直してください。",
}

return {
	{
		"zbirenbaum/copilot.lua",
		cmd = "Copilot",
		event = "InsertEnter",
		config = function()
			-- 元の vim.lsp.util.apply_text_edits をラップ
			local original_apply_text_edits = vim.lsp.util.apply_text_edits

			-- 新しい apply_text_edits を定義し、utf-8 に強制する
			vim.lsp.util.apply_text_edits = function(edits, bufnr, encoding)
				-- encoding を utf-8 に強制
				encoding = "utf-8"
				-- 元の関数を呼び出す
				original_apply_text_edits(edits, bufnr, encoding)
			end

			require("copilot").setup({
				suggestion = {
					enabled = true,
					auto_trigger = true, -- 自動で提案が表示されるように
					keymap = {
						accept = "<C-l>", -- 提案を受け入れる
						next = "<M-]>", -- 次の提案に移動
						prev = "<M-[>", -- 前の提案に移動
						dismiss = "<C-]>", -- 提案を無視する
					},
				},
				panel = {
					enabled = true, -- 提案パネルを有効化
					auto_refresh = true, -- 自動的に提案を更新
					keymap = {
						open = "<M-p>", -- パネルを開くキー
						accept = "<C-l>", -- 提案を受け入れる
						jump_prev = "[[", -- 前の提案へジャンプ
						jump_next = "]]", -- 次の提案へジャンプ
						refresh = "gr", -- 提案を手動でリフレッシュ
					},
					layout = {
						position = "bottom", -- パネルを下に配置
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
					["*"] = true, -- 全てのファイルタイプで有効
				},
				copilot_node_command = "node", -- 使用するNode.jsのパス

				-- LSPサーバーのオプションをオーバーライド
				server_opts_overrides = {},
			})

			-- 自動サインイン
			require("copilot.auth").signin()
		end,
	},
	{
		"CopilotC-Nvim/CopilotChat.nvim",
		branch = "canary",
		dependencies = {
			{ "zbirenbaum/copilot.lua" }, -- Copilotのコアモジュール
			{ "nvim-lua/plenary.nvim" }, -- Neovimのユーティリティ関数を提供
		},
		build = "make tiktoken", -- MacOSやLinux向けビルド
		opts = {
			debug = true, -- デバッグを有効化
			model = "gpt-4o", -- 使用するモデルを指定 ('gpt-3.5-turbo', 'gpt-4', 'gpt-4o' など)
			auto_insert_mode = true,
			auto_follow_cursor = true, -- 自動的に最新の結果にフォーカス
			clear_chat_on_new_prompt = false, -- 新しいプロンプトでチャットをクリア
			show_help = true,
			question_header = "  " .. vim.env.USER or "User" .. " ",
			answer_header = "  Copilot ",
			window = {
				width = 0.5, -- ウィンドウの幅を50%に拡大
			},
			selection = function(source)
				local select = require("CopilotChat.select")
				return select.visual(source) or select.buffer(source)
			end,
			mappings = {
				submit_prompt = {
					normal = "<CR>", -- 通常モードでEnterキーでプロンプトを送信
					insert = "<CR><CR>", -- 挿入モードでEnter
				},
			},
			system_prompt = "Your name is Github Copilot and you are a AI assistant for developers. response language is Japanese.",
			prompts = prompts,
		},
		config = function(_, opts)
			-- CopilotChatのセットアップ
			local chat = require("CopilotChat")
			chat.setup(opts)

			-- コマンド作成
			vim.api.nvim_create_user_command("CopilotChatVisual", function(args)
				chat.ask(args.args, { selection = require("CopilotChat.select").visual })
			end, { nargs = "*", range = true })

			-- インラインチャットの設定
			vim.api.nvim_create_user_command("CopilotChatInline", function(args)
				chat.ask(args.args, {
					selection = require("CopilotChat.select").visual,
					window = {
						layout = "float",
						relative = "cursor",
						width = 1,
						height = 0.4,
						row = 1,
					},
				})
			end, { nargs = "*", range = true })

			-- cmp統合の設定
			require("CopilotChat.integrations.cmp").setup()

			-- チャットバッファで行番号を非表示
			vim.api.nvim_create_autocmd("BufEnter", {
				pattern = "copilot-chat",
				callback = function()
					vim.opt_local.relativenumber = false
					vim.opt_local.number = false
				end,
			})
		end,
		cmd = {
			"CopilotChat",
			"CopilotChatClose",
			"CopilotChatDebugInfo",
			"CopilotChatLoad",
			"CopilotChatOpen",
			"CopilotChatReset",
			"CopilotChatSave",
			"CopilotChatToggle",

			-- Default prompts
			"CopilotChatCommit",
			"CopilotChatCommitStaged",
			"CopilotChatDocs",
			"CopilotChatExplain",
			"CopilotChatFix",
			"CopilotChatFixDiagnostic",
			"CopilotChatOptimize",
			"CopilotChatReview",
			"CopilotChatTests",

			-- User commands
			"CopilotChatInline",
			"CopilotChatVisual",
		},
		keys = {
			{ "<leader>co", "<cmd>CopilotChatOpen<cr>", desc = "Open" },
			{ "<leader>cc", "<cmd>CopilotChatClose<cr>", desc = "Close" },
			{ "<leader>ct", "<cmd>CopilotChatToggle<cr>", desc = "Toggle" },
			{ "<leader>cf", "<cmd>CopilotChatFixDiagnostic<cr>", desc = "Fix Diagnostic" },
			{
				"<leader>cr",
				"<cmd>CopilotChatReset<cr>",
				desc = "Reset",
			},
			{
				"<leader>cD",
				"<cmd>CopilotChatDebugInfo<cr>",
				desc = "Debug info",
			},
			{
				"<leader>chh",
				function()
					local actions = require("CopilotChat.actions")
					require("CopilotChat.integrations.telescope").pick(actions.help_actions())
				end,
				desc = "Help actions",
			},
			{
				"<leader>cp",
				function()
					local actions = require("CopilotChat.actions")
					require("CopilotChat.integrations.telescope").pick(actions.prompt_actions(), {
						layout_strategy = "horizontal", -- horizontalレイアウトを指定
						layout_config = {
							width = 0.8, -- ウィンドウの幅を80%に設定
							height = 0.6, -- 高さを60%に設定
							preview_width = 0.5, -- プレビューウィンドウの幅を50%に設定
						},
					})
				end,
				desc = "Prompt actions",
			},
			{
				"<leader>cm",
				"<cmd>CopilotChatCommit<cr>",
				desc = "Generate commit message for all changes",
			},
			{
				"<leader>cM",
				"<cmd>CopilotChatCommitStaged<cr>",
				desc = "Generate commit message for staged changes",
			},
			{
				"<leader>ci",
				function()
					local input = vim.fn.input("Ask Copilot: ")
					if input ~= "" then
						vim.cmd("CopilotChat " .. input)
					end
				end,
				desc = "Ask input",
			},
			{
				"<leader>cq",
				function()
					local input = vim.fn.input("Quick Chat: ")
					if input ~= "" then
						require("CopilotChat").ask(input, { selection = require("CopilotChat.select").buffer })
					end
				end,
				desc = "Quick chat",
			},
			{
				"<leader>cp",
				":lua require('CopilotChat.integrations.telescope').pick(require('CopilotChat.actions').prompt_actions({selection = require('CopilotChat.select').visual}))<CR>",
				mode = "x",
				desc = "Prompt actions",
			},
			{
				"<leader>cv",
				":CopilotChatVisual",
				mode = "x",
				desc = "Open in vertical split",
			},
			{
				"<leader>ci",
				":CopilotChatInline<cr>",
				mode = "x",
				desc = "Inline chat",
			},
		},
	},
}
