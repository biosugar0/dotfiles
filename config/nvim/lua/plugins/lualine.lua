return {
	{
		"rcarriga/nvim-notify",
		config = function()
			-- 必須設定: ターミナルで 24bit カラーを有効化
			vim.opt.termguicolors = true

			-- デフォルトの通知関数として `nvim-notify` を使用
			vim.notify = require("notify")

			-- `nvim-notify` の設定
			require("notify").setup({
				-- 通知レベル（エラーレベル以上の通知のみ表示）
				level = "info", -- "info", "warn", "error", "debug" などが選択可能

				-- 通知の最大高さ
				max_height = function()
					return math.floor(vim.o.lines * 0.75)
				end,

				-- 通知の最大幅
				max_width = function()
					return math.floor(vim.o.columns * 0.75)
				end,

				-- アイコンのカスタマイズ
				icons = {
					ERROR = "",
					WARN = "",
					INFO = "",
					DEBUG = "",
					TRACE = "✎",
				},

				-- フォーマットのカスタマイズ
				time_formats = {
					default = "%H:%M:%S",
					seconds = "%S 秒前",
				},

				-- 通知終了時に呼ばれるコールバック
				on_close = function(win)
					print("Notification closed")
				end,

				-- 通知が開かれたときに呼ばれるコールバック
				on_open = function(win)
					print("Notification opened")
				end,

				-- 最小幅
				minimum_width = 30,

				-- 通知アニメーションのフレームレート
				fps = 60,

				-- 通知のレンダリングスタイル
				render = "default", -- 他には "minimal", "compact", "wrapped-default" などがある

				-- アニメーションスタイル: "fade", "slide", "static" など
				stages = "fade_in_slide_out",

				-- 最後の通知を一定時間表示し続ける
				timeout = 3000, -- 3秒表示

				-- 背景の透明度
				background_colour = "#000000",

				-- 通知履歴を表示するためのウィンドウを制御
				top_down = false, -- 通知を上から表示
			})

			-- `Telescope` の拡張機能として `notify` を読み込む
			if pcall(require, "telescope") then
				require("telescope").load_extension("notify")
			end

			-- キーマッピング
			vim.keymap.set(
				"n",
				"<leader>nh",
				":Notifications<CR>",
				{ silent = true, noremap = true, desc = "通知履歴を表示" }
			)
		end,
	},
	{
		"nvim-lualine/lualine.nvim", -- Specify the lualine plugin
		dependencies = {
			"kyazdani42/nvim-web-devicons",
		},
		event = "VimEnter",
		config = function()
			-- The lualine configuration, migrated from your previous setup
			require("lualine").setup({
				options = {
					icons_enabled = true,
					theme = "nightfly", -- Set your theme
					component_separators = { left = "|", right = "|" },
					section_separators = { left = "", right = "" },
					disabled_filetypes = {},
					always_divide_middle = true,
					colored = true,
					globalstatus = true,
				},
				sections = {
					lualine_a = { "mode" },
					lualine_b = { "branch", "diff" },
					lualine_c = {
						{
							"filename",
							path = 1,
							file_status = true,
							shorting_target = 40,
							symbols = {
								modified = " [+]",
								readonly = " [RO]",
								unnamed = "Untitled",
							},
						},
					},
					lualine_x = { "filetype", "encoding" },
					lualine_y = {
						{
							"diagnostics",
							source = { "nvim_diagnostic" },
						},
					},
					lualine_z = { "location" },
				},
				inactive_sections = {
					lualine_a = {},
					lualine_b = {},
					lualine_c = { "filename" },
					lualine_x = { "location" },
					lualine_y = {},
					lualine_z = {},
				},
				tabline = {},
				extensions = {},
			})
		end,
	},
}
