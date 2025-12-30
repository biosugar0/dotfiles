return {
  -- SmoothCursorプラグインの設定
  {
    'gen740/SmoothCursor.nvim',
    event = 'VeryLazy', -- 遅延ロード
    config = function()
      local conf = {
        autostart = true,
        cursor = '', -- カーソルの形状 (Nerd Fontが必要)
        linehl = nil, -- カーソル行のハイライト。
        type = 'default', -- "default"または"exp" (カーソルの移動計算関数)
        fancy = {
          enable = true, -- fancyモードの有効化
          head = { cursor = '⊛', texthl = 'SmoothCursorAqua', linehl = nil },
          body = {
            { cursor = '⊛', texthl = 'SmoothCursorAqua' },
            { cursor = '⊛', texthl = 'SmoothCursorAqua' },
            { cursor = '•', texthl = 'SmoothCursorAqua' },
            { cursor = '•', texthl = 'SmoothCursorAqua' },
            { cursor = '.', texthl = 'SmoothCursorAqua' },
            { cursor = '.', texthl = 'SmoothCursorAqua' },
          },
          tail = { cursor = nil, texthl = 'SmoothCursorAqua' },
        },
        speed = 25, -- 最大100, 現在位置に張り付く速度
        intervals = 35, -- ティック間隔
        priority = 10, -- マーカープライオリティ
        timeout = 3000, -- タイムアウト
        threshold = 3, -- 移動閾値
        texthl = 'SmoothCursor', -- ハイライトグループ
      }

      require('smoothcursor').setup(conf)
    end,
  },
}
