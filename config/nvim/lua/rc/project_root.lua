-- プロジェクトルート自動検出
-- vim.fs.root()を使用してプロジェクトルートを検出し、自動的にlcdする

local markers = { ".git", "Makefile", "package.json", "go.mod", "pyproject.toml" }

local function set_cwd_if_needed(buf)
	local root = vim.fs.root(buf, markers)
	if root and root ~= vim.fn.getcwd() then
		vim.cmd.lcd(root) -- buffer-localなcd
	end
end

vim.api.nvim_create_autocmd({ "BufEnter", "DirChanged" }, {
	callback = function(args)
		-- 特殊バッファをスキップ
		if vim.bo[args.buf].buftype == "" then
			set_cwd_if_needed(args.buf)
		end
	end,
})
