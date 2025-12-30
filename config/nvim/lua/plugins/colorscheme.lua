return {
  {
    'cocopon/iceberg.vim',
    config = function()
      -- カラースキームの設定
      vim.cmd([[colorscheme iceberg]])

      -- ハイライトをカスタマイズするためのautocmd
      vim.api.nvim_create_augroup('MyColor', { clear = true })

      vim.api.nvim_create_autocmd('ColorScheme', {
        group = 'MyColor',
        pattern = '*',
        callback = function()
          -- カラースキームがロードされた際にハイライトをカスタマイズ
          vim.cmd([[
                      hi Normal guibg=#000000
                      hi SignColumn guibg=#000000
                      hi GitGutterAdd ctermfg=150 ctermbg=235 guifg=#b4be82 guibg=#000000
                      hi GitGutterChange ctermfg=109 ctermbg=235 guifg=#89b8c2 guibg=#000000
                      hi GitGutterChangeDelete ctermfg=109 ctermbg=235 guifg=#89b8c2 guibg=#000000
                      hi GitGutterDelete ctermfg=203 ctermbg=235 guifg=#e27878 guibg=#000000
                      hi NormalFloat guibg=#1f2335
                      hi FloatBorder guifg=white guibg=#1f2335 blend=20
                      hi Pmenu ctermfg=251 ctermbg=236 guifg=#c6c8d1 guibg=#1f2335 blend=20
                      hi VertSplit cterm=NONE ctermbg=233 ctermfg=233 gui=NONE guibg=#000000 guifg=#253f4d
                    ]])
        end,
      })
    end,
  },
}
