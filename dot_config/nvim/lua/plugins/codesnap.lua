return {
  {
    'mistricky/codesnap.nvim',
    build = 'make',
    keys = {
      -- 選択したコードをクリップボードにコピー
      { '<leader>xx', '<cmd>CodeSnap<cr>', mode = 'x', desc = 'Copy selected code snapshot into clipboard' },
      -- 選択したコードをファイルに保存
      { '<leader>cs', '<cmd>CodeSnapSave<cr>', mode = 'x', desc = 'Save selected code snapshot into file' },
    },
    opts = {
      -- スナップショットの保存先 (画像として保存したい場合に使用)
      save_path = '~/Desktop',
      -- パンくずリストを非表示
      has_breadcrumbs = false,
      -- 行番号を非表示
      has_line_number = false,
      -- Mac風のウィンドウスタイルを有効化
      mac_window_bar = false,
      -- パディングを0に設定
      bg_padding = 0,
      -- ウォーターマークを非表示
      watermark = '',
    },
  },
}
