return {
	"nvim-treesitter/nvim-treesitter",
	build = ":TSUpdate",
	dependencies = {
		{ "JoosepAlviste/nvim-ts-context-commentstring" },
		{ "m-demare/hlargs.nvim" },
		{ "nvim-treesitter/nvim-treesitter-textobjects" },
		{ "mfussenegger/nvim-treehopper" },
		{ "bennypowers/nvim-regexplainer" },
		{ "nvim-treesitter/nvim-treesitter-context" },
	},
	config = function()
		-- カスタム言語登録
		vim.treesitter.language.register("json", "tfstate")
		vim.treesitter.language.register("terraform", "tf")
		vim.treesitter.language.register("terraform", "tfvars")
		vim.treesitter.language.register("bash", "zsh")
		vim.treesitter.language.register("gitcommit", "gina-commit")

		-- Treesitter設定
		require("nvim-treesitter.configs").setup({
			ensure_installed = {
				"vim",
				"toml",
				"python",
				"go",
				"hcl",
				"yaml",
				"bash",
				"sql",
				"json",
				"typescript",
				"tsx",
				"terraform",
				"lua",
				"gitcommit",
			},
			ignore_install = {},
			sync_install = false,
			auto_install = true,
			highlight = {
				enable = true,
				disable = { "ruby", "c_sharp", "vue" },
			},
			indent = {
				enable = true,
			},
			incremental_selection = {
				enable = true,
				keymaps = {
					init_selection = "gnn", -- 選択開始
					node_incremental = "grn", -- ノードを拡張選択
					scope_incremental = "grc",
					node_decremental = "grm", -- 選択縮小
				},
			},
			matchup = {
				enable = true,
				include_match_words = true,
			},
			additional_vim_regex_highlighting = false,
		})

		require("ts_context_commentstring").setup({
			enable = true,
			enable_autocmd = false,
			config = {
				lua = "-- %s",
				toml = "# %s",
				yaml = "# %s",
			},
		})

		require("hlargs").setup()

		require("treesitter-context").setup()
		vim.treesitter.query.add_directive("directivename", function() end, true)
	end,
}
