return {
	{
		"shellRaining/hlchunk.nvim",
		event = "BufRead",
		config = function()
			require("hlchunk").setup({
				exclude_filetypes = {
					"gin",
					"gin-diff",
					"gin-edit",
					"gin-status",
					"gin-commit",
					"gin-log",
					"gin-branch",
					"gin-merge",
					"gin-rebase",
					"gin-patch",
					"gin-diff",
					"gin-blame",
					"gin-stash",
					"denops",
					"denops-std-buffer",
					"denops-buffer",
					"denops-float",
					"denops-popup",
					"denops-preview",
				},
				chunk = {
					enable = true,
					notify = true,
					use_treesitter = true,
					chars = {
						horizontal_line = "─",
						vertical_line = "│",
						left_top = "╭",
						left_bottom = "╰",
						right_arrow = ">",
					},
					textobject = "",
					max_file_size = 1024 * 1024, -- 1MB
					error_sign = true,
				},
				indent = {
					enable = true,
					use_treesitter = true,
					chars = {
						"│",
					},
				},
				line_num = {
					enable = false,
					use_treesitter = true,
				},
				blank = {
					enable = false,
				},
			})
		end,
	},
}
