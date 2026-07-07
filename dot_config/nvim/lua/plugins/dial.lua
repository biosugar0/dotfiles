return {
	-- dijal.nvimの設定
	{
		"monaqa/dial.nvim",
		event = "BufRead",
		config = function()
			local augend = require("dial.augend")
			require("dial.config").augends:register_group({
				default = {
					augend.integer.alias.decimal, -- 10進数の整数
					augend.integer.alias.hex, -- 16進数の整数
					augend.date.alias["%Y/%m/%d"], -- 日付
					augend.date.alias["%Y-%m-%d"], -- 日付
					augend.date.alias["%m/%d"], -- 月/日
					augend.date.alias["%H:%M"], -- 時間
					augend.constant.alias.bool, -- ブール値
					augend.semver.alias.semver, -- セマンティックバージョン
					augend.constant.alias.ja_weekday_full, -- 日本語の曜日
					augend.case.new({
						types = { "camelCase", "snake_case", "PascalCase", "SCREAMING_SNAKE_CASE" },
						cyclic = true, -- ケースの循環
					}),
				},
			})
			vim.keymap.set("n", "<C-a>", function()
				require("dial.map").manipulate("increment", "normal")
			end)
			vim.keymap.set("n", "<C-x>", function()
				require("dial.map").manipulate("decrement", "normal")
			end)
			vim.keymap.set("n", "g<C-a>", function()
				require("dial.map").manipulate("increment", "normal")
			end)
			vim.keymap.set("n", "g<C-x>", function()
				require("dial.map").manipulate("decrement", "normal")
			end)
			vim.keymap.set("v", "<C-a>", function()
				require("dial.map").manipulate("increment", "visual")
			end)
			vim.keymap.set("v", "<C-x>", function()
				require("dial.map").manipulate("decrement", "visual")
			end)
			vim.keymap.set("v", "g<C-a>", function()
				require("dial.map").manipulate("increment", "visual")
			end)
			vim.keymap.set("v", "g<C-x>", function()
				require("dial.map").manipulate("decrement", "visual")
			end)
		end,
		keys = {
			{ "<C-a>", mode = { "n", "v" } },
			{ "<C-x>", mode = { "n", "v" } },
			{ "g<C-a>", mode = { "n", "v" } },
			{ "g<C-x>", mode = { "n", "v" } },
		},
	},
}
