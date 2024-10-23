return {
    {
        "nvim-telescope/telescope.nvim",
        cmd = { "Telescope" },
        keys = {
            { "<Leader>f",  "<cmd>Telescope find_files<CR>",                    silent = true },
            { "<Leader>gf", "<cmd>Telescope git_files<CR>",                     silent = true },
            { "<Leader>gF", "<cmd>Telescope git_files show_untracked=true<CR>", silent = true },
            { "<Leader>b",  "<cmd>Telescope buffers<CR>",                       silent = true },
            { "<Leader>l",  "<cmd>Telescope current_buffer_fuzzy_find<CR>",     silent = true },
            { "<Leader>h",  "<cmd>Telescope oldfiles<CR>",                      silent = true },
            { "<Leader>m",  "<cmd>Telescope marks<CR>",                         silent = true },
            { "<Leader>R",  "<cmd>Telescope live_grep<CR>",                     silent = true },
            { "<Leader>p",  "<cmd>Telescope ghq list<CR>",                      silent = true }, -- ghq で管理しているプロジェクトを表示
        },
        dependencies = {
            { "nvim-lua/plenary.nvim" },
            { "nvim-telescope/telescope-fzf-native.nvim",  build = "make" },
            { "nvim-telescope/telescope-file-browser.nvim" },
            { "nvim-telescope/telescope-ghq.nvim" }, -- ghq エクステンション
        },
        config = function()
            local actions = require("telescope.actions")

            require("telescope").setup({
                defaults = {
                    layout_strategy = "horizontal",
                    layout_config = {
                        preview_cutoff = 120,
                        width = 0.8,
                        height = 0.8,
                        prompt_position = "top",
                        preview_width = 0.6,
                    },
                    sorting_strategy = "ascending",
                    prompt_prefix = "🔍 ",
                    selection_caret = " ",
                    mappings = {
                        i = {
                            ["<C-j>"] = actions.move_selection_next, -- Ctrl-j で次の項目へ
                            ["<C-k>"] = actions.move_selection_previous, -- Ctrl-k で前の項目へ
                            ["<C-t>"] = actions.select_tab,
                            ["<C-s>"] = actions.select_horizontal,
                            ["<C-v>"] = actions.select_vertical,
                            ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
                            ["<Esc>"] = actions.close,
                        },
                        n = {
                            ["<C-j>"] = actions.move_selection_next, -- ノーマルモードでも Ctrl-j/k をサポート
                            ["<C-k>"] = actions.move_selection_previous,
                            ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
                        },
                    },
                    file_ignore_patterns = { "node_modules", ".git/", "vendor" },
                },
                pickers = {
                    find_files = {
                        hidden = true,
                        find_command = { "rg", "--files", "--hidden", "--glob", "!.git/**" },
                    },
                    live_grep = {
                        additional_args = function()
                            return { "--hidden" }
                        end,
                    },
                },
                extensions = {
                    fzf = {
                        fuzzy = true,
                        override_generic_sorter = true,
                        override_file_sorter = true,
                        case_mode = "smart_case",
                    },
                    file_browser = {
                        hijack_netrw = true,
                    },
                    ghq = {
                        sort_by = "path",
                    },
                },
            })

            -- FZF拡張、ファイルブラウザ、ghq拡張の読み込み
            require("telescope").load_extension("fzf")
            require("telescope").load_extension("file_browser")
            require("telescope").load_extension("ghq")
        end,
    },
}
