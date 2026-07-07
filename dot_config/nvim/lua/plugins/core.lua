return {
	{
		"nvim-tree/nvim-web-devicons",
		event = { "VeryLazy" },
	},
	{
		"vim-denops/denops.vim",
		event = "VeryLazy", -- Load after startup, but before most operations
	},
	{
		"folke/lazy.nvim",
		cmd = { "Lazy", "LazyAll" },
		init = function()
			vim.keymap.set({ "n" }, "<Leader>L", "<Cmd>Lazy<CR>")

			-- Load all plugins
			local did_load_all = false
			vim.api.nvim_create_user_command("LazyAll", function()
				if did_load_all then
					return
				end

				local specs = require("lazy").plugins()
				local names = {}
				for _, spec in pairs(specs) do
					if spec.lazy and not spec["_"].loaded and not spec["_"].dep then
						table.insert(names, spec.name)
					end
				end
				require("lazy").load({ plugins = names })
				did_load_all = true
			end, {})
		end,
	},
	{ "tani/vim-artemis" },
	{
		"kana/vim-operator-user",
		event = { "VeryLazy" },
	},
	{ "kana/vim-textobj-user" },
	{ "tpope/vim-repeat", event = { "VeryLazy" } },
	{
		"machakann/vim-textobj-delimited",
		dependencies = { "kana/vim-textobj-user" },
		keys = { "vid", "viD", "vad", "vaD" },
	},
	{
		"sgur/vim-textobj-parameter",
		dependencies = { "kana/vim-textobj-user" },
		keys = { "i,", "a," },
		event = { "VeryLazy" },
	},
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			-- your configuration comes here
			-- or leave it empty to use the default settings
			-- refer to the configuration section below
		},
		keys = {
			{
				"<leader>?",
				function()
					require("which-key").show({ global = false })
				end,
				desc = "Buffer Local Keymaps (which-key)",
			},
		},
	},
}
