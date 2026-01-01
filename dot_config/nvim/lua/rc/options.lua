local set = vim.opt
local let = vim.o

set.shell = "zsh"

set.nrformats:append("octal") -- 10進数のみ
set.nrformats:append("unsigned") --数字の増加減少でマイナスを扱わない

set.clipboard = "unnamed,unnamedplus" -- OSのクリップボードをレジスタ指定無しで Yank, Put 出来るようにする
let.completeopt = "menuone"

---- 移動設定
set.backspace = "indent,eol,start" -- Backspaceキーの影響範囲に制限を設けない
set.whichwrap = "b,s,h,l,<,>,[,]" -- 行頭行末の左右移動で行をまたぐ
set.scrolloff = 8 -- 上下8行の視界を確保
set.sidescrolloff = 16 -- 左右スクロール時の視界を確保
set.sidescroll = 1 -- 左右スクロールは一文字づつ行う
set.startofline = false -- 移動時にx軸をそのままにする
set.mouse = "" -- マウス無効
set.virtualedit = "all" -- allow virtual editing in all modes
----保存時の設定
local undodir = vim.env.CACHE .. "/nvim/undo"
set.undodir:append(undodir)
if vim.fn.isdirectory(undodir) == 0 then
	vim.fn.mkdir(undodir, "p")
end
set.undofile = true
---- バックアップ関連
set.writebackup = false
set.backup = false
set.swapfile = false
set.backupdir:remove(".")
set.shada = [['100,<20,s10,h]]
----ファイル処理関連
set.confirm = true -- 保存されていないファイルがあるときは終了前に保存確認
set.hidden = true -- 保存されていないファイルがあるときでも別のファイルを開くことが出来る
set.autoread = true -- 外部でファイルに変更がされた場合は読みなおす
set.isfname:append("32") -- spaceを追加
set.isfname:remove("=") -- = を除外
----検索設定
set.hlsearch = true -- 検索文字列をハイライトする
set.incsearch = true -- インクリメンタルサーチを行う
set.ignorecase = true -- 大文字と小文字を区別しない
set.smartcase = true -- 大文字と小文字が混在した言葉で検索を行った場合に限り、大文字と小文字を区別する
set.wrapscan = true -- 最後尾まで検索を終えたら次の検索で先頭に移る
--コマンドライン関連
set.history = 1000 -- コマンドラインの履歴を1000件保存する
set.wildmenu = true
set.wildignorecase = true -- コマンド補完で大文字小文字を区別しない
set.wildmode = "list:longest,full" -- コマンドラインモードでTABキーによるファイル名補完を有効にする
-- 表示設定
set.diffopt = "internal,filler,closeoff,vertical"
set.laststatus = 3 --
set.cmdheight = 1 -- メッセージ表示欄を1行確保
set.showmatch = true -- 対応する括弧を強調表示
set.matchtime = 2
set.helpheight = 999 -- ヘルプを画面いっぱいに開く
set.conceallevel = 2
set.list = true -- 不可視文字を表示
set.breakindent = true -- インデントされた行の折り返しを綺麗に
set.signcolumn = "auto"
set.redrawtime = 300
set.ambiwidth = "single"
set.fillchars = {
	eob = " ",
	horiz = "━",
	horizup = "┻",
	horizdown = "┳",
	vert = "┃",
	vertleft = "┫",
	vertright = "┣",
	verthoriz = "╋",
}
-- 不可視文字の表示記号指定
vim.opt.listchars = {
	tab = "|-",
	trail = "-",
	nbsp = "%",
	eol = "↲",
	extends = "❯",
	precedes = "❮",
}
set.ttyfast = true
vim.o.pumblend = 20 -- ポップアップメニューを半透明に
-- タブ、インデント設定
set.expandtab = true -- タブ入力を複数の空白入力に置き換える
set.tabstop = 4 -- 画面上でタブ文字が占める幅
set.shiftwidth = 4 -- 自動インデントでずれる幅
set.softtabstop = 4 -- 連続した空白に対してタブキーやバックスペースキーでカーソルが動く幅
set.autoindent = true -- 改行時に前の行のインデントを継続する
set.smartindent = true -- 改行時に入力された行の末尾に合わせて次の行のインデントを増減する

-- Python provider setup (optimized for startup time)
-- Use NEOVIM_PYTHON env var or default venv location
local function setup_python_provider()
	local py = vim.env.NEOVIM_PYTHON or vim.fn.stdpath("data") .. "/venv/bin/python3"

	if vim.fn.executable(py) == 1 then
		vim.g.python3_host_prog = py
		return
	end

	-- Only create venv if it doesn't exist (deferred to avoid blocking startup)
	local venv_path = vim.fn.stdpath("data") .. "/venv"
	if vim.fn.isdirectory(venv_path) == 0 then
		vim.notify("Creating Python venv for Neovim...", vim.log.levels.INFO)
		vim.fn.jobstart({
			"python3",
			"-m",
			"venv",
			venv_path,
			"--prompt",
			"nvim",
		}, {
			on_exit = function()
				vim.fn.jobstart({
					venv_path .. "/bin/python",
					"-m",
					"pip",
					"install",
					"--upgrade",
					"pip",
					"pynvim",
				})
			end,
		})
	end
	vim.g.python3_host_prog = venv_path .. "/bin/python3"
end

-- Defer Python provider setup to after startup
vim.api.nvim_create_autocmd("VimEnter", {
	once = true,
	callback = setup_python_provider,
})
