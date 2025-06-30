local M = {}

-- Helper function to create temporary files with prompts
local function create_prompt_file(prompt_text)
  local temp_dir = vim.fn.stdpath('cache') .. '/claude_prompts'
  vim.fn.mkdir(temp_dir, 'p')
  local temp_file = temp_dir .. '/prompt_' .. os.time() .. '.md'

  local lines = {
    '# Claude Code Request',
    '',
    prompt_text,
    '',
    '---',
    '*This prompt was auto-generated. Edit as needed and send to Claude Code.*',
  }

  vim.fn.writefile(lines, temp_file)
  return temp_file
end

-- Execute prompt using Claude CLI directly (faster than WebSocket)
local function execute_prompt(prompt_text, add_current_file)
  -- Create safe prompt file for complex content
  local temp_file = create_prompt_file(prompt_text)

  -- Build claude CLI command with context if needed
  local cmd = 'claude -p'

  if add_current_file then
    local current_file = vim.fn.expand('%:p')
    local current_dir = vim.fn.expand('%:p:h')

    if current_file and current_file ~= '' then
      -- Add current directory for context
      cmd = cmd .. ' --add-dir ' .. vim.fn.shellescape(current_dir)

      -- Add current file content to prompt
      local file_content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
      local enhanced_prompt = string.format(
        [[
Current file: %s

File content:
```%s
%s
```

%s]],
        current_file,
        vim.bo.filetype or '',
        file_content,
        prompt_text
      )

      -- Update temp file with enhanced prompt
      vim.fn.delete(temp_file)
      temp_file = create_prompt_file(enhanced_prompt)
    end
  end

  cmd = cmd .. ' < ' .. vim.fn.shellescape(temp_file)

  vim.notify('Executing with Claude CLI...', vim.log.levels.INFO, {
    title = 'Claude Code',
    timeout = 1000,
  })

  -- Execute asynchronously and handle response
  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data and #data > 0 then
        local response = table.concat(data, '\n')
        if response:match('%S') then -- Non-empty response
          -- Display response in popup
          local buf = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(response, '\n'))
          vim.bo[buf].filetype = 'markdown'
          vim.bo[buf].readonly = true

          -- Calculate popup size
          local lines = vim.split(response, '\n')
          local max_width = 0
          for _, line in ipairs(lines) do
            max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
          end

          local width = math.min(max_width + 4, vim.o.columns - 10)
          local height = math.min(#lines + 2, vim.o.lines - 10)

          -- Create popup window
          local win = vim.api.nvim_open_win(buf, true, {
            relative = 'editor',
            width = width,
            height = height,
            col = math.floor((vim.o.columns - width) / 2),
            row = math.floor((vim.o.lines - height) / 2),
            style = 'minimal',
            border = 'rounded',
            title = ' Claude Response ',
            title_pos = 'center',
          })

          -- Set popup-specific keymaps
          local opts = { buffer = buf, silent = true }
          vim.keymap.set('n', 'q', '<cmd>close<cr>', opts)
          vim.keymap.set('n', '<Esc>', '<cmd>close<cr>', opts)
          vim.keymap.set('n', '<CR>', '<cmd>close<cr>', opts)
          vim.keymap.set('n', 'y', function()
            vim.fn.setreg('+', response)
            vim.notify('✓ Copied to clipboard', vim.log.levels.INFO, { timeout = 1000 })
          end, opts)

          -- Brief success notification
          vim.notify('✓ Complete (press q to close)', vim.log.levels.INFO, {
            title = 'Claude',
            timeout = 2000,
          })
        end
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 0 then
        local error_msg = table.concat(data, '\n'):gsub('^%s*', ''):gsub('%s*$', '')
        -- Only show error if there's actual content (not just whitespace)
        if error_msg ~= '' then
          vim.notify('Claude CLI Error: ' .. error_msg, vim.log.levels.ERROR, {
            title = 'Claude Code Error',
            timeout = 5000,
          })
        end
      end
    end,
    on_exit = function(_, code)
      -- Clean up temp file
      vim.fn.delete(temp_file)

      if code == 0 then
        -- Success - no additional notification needed
      else
        vim.notify('Claude CLI exited with code: ' .. code, vim.log.levels.WARN, {
          title = 'Claude Code Warning',
          timeout = 3000,
        })
      end
    end,
  })
end

-- Automatic prompt execution with Claude CLI
local function send_enhanced_prompt(prompt_text, add_current_file)
  execute_prompt(prompt_text, add_current_file)
end

-- Smart diagnostic context gathering
local function get_diagnostic_context()
  local diagnostics = vim.diagnostic.get(0, { lnum = vim.fn.line('.') - 1 })
  local context = ''

  if #diagnostics > 0 then
    local diag = diagnostics[1]
    context = string.format(
      'Diagnostic Error:\n- Source: %s\n- Severity: %s\n- Message: %s\n- Line: %d\n\n',
      diag.source or 'LSP',
      vim.diagnostic.severity[diag.severity] or 'ERROR',
      diag.message,
      diag.lnum + 1
    )
  end

  return context
end

-- Git context gathering
local function get_git_context()
  local git_status = vim.fn.systemlist('git status --porcelain 2>/dev/null')
  local git_diff = vim.fn.systemlist('git diff --cached 2>/dev/null')

  if vim.v.shell_error ~= 0 or #git_diff == 0 then
    git_diff = vim.fn.systemlist('git diff 2>/dev/null')
  end

  local context = ''

  if #git_status > 0 then
    context = context .. 'Changed files:\n' .. table.concat(git_status, '\n') .. '\n\n'
  end

  if #git_diff > 0 and #git_diff < 50 then -- Avoid overwhelming Claude with large diffs
    context = context .. 'Recent changes:\n```diff\n' .. table.concat(git_diff, '\n') .. '\n```\n\n'
  end

  return context
end

-- Enhanced file context with metadata
local function add_file_with_context()
  local file_path = vim.fn.expand('%:p')
  local file_type = vim.bo.filetype
  local line_count = vim.fn.line('$')
  local current_line = vim.fn.line('.')

  vim.cmd('ClaudeCodeAdd')

  local context = string.format(
    'File: %s\nType: %s\nLines: %d\nCurrent position: line %d\n',
    file_path,
    file_type,
    line_count,
    current_line
  )

  vim.notify('Added to Claude context: ' .. context, vim.log.levels.INFO)
end

-- Get selected text using a simpler, more reliable method
local function get_visual_selection()
  -- Force exit visual mode and use marks
  vim.cmd('normal! \27') -- ESC to exit visual mode

  -- Get visual selection marks
  local start_row, start_col = unpack(vim.api.nvim_buf_get_mark(0, '<'))
  local end_row, end_col = unpack(vim.api.nvim_buf_get_mark(0, '>'))

  if start_row == 0 or end_row == 0 then
    return ''
  end

  -- Get the lines
  local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)

  if #lines == 0 then
    return ''
  end

  -- Handle single line
  if #lines == 1 then
    return string.sub(lines[1], start_col, end_col + 1)
  end

  -- Handle multiple lines
  lines[1] = string.sub(lines[1], start_col)
  lines[#lines] = string.sub(lines[#lines], 1, end_col + 1)

  return table.concat(lines, '\n')
end

-- Translation function for selected text
local function translate_selection()
  local text = get_visual_selection()

  -- Debug information
  local mode = vim.fn.mode()
  local debug_info = string.format('Mode: %s, Text length: %d', mode, text and #text or 0)

  if text == '' or text == nil then
    vim.notify('No text selected for translation. ' .. debug_info, vim.log.levels.WARN)
    return
  end

  local prompt = string.format(
    [[
あなたは日英翻訳の専門家です。以下のテキストを翻訳してください：

**翻訳対象テキスト:**
```
%s
```

**翻訳指示:**
1. 言語を自動検出し、日本語→英語、その他言語→日本語に翻訳
2. 自然で正確な表現を維持
3. 元の文脈とニュアンスを保持
4. 必要に応じて文化的な説明を追加
5. テキストが長い場合は、省略せずに全文を翻訳

**翻訳結果のみを出力してください（説明は不要）**
]],
    text
  )

  execute_prompt(prompt, false)
end

-- Japanese system prompt for better interactions
local function get_japanese_system_prompt()
  return [[
あなたは "Claude Code" というAIプログラミングアシスタントです。
Neovimエディタに統合されており、ユーザーの開発作業を効率的に支援します。

## 主要な役割:
- プログラミングに関する質問への回答
- コードの解説・レビュー・最適化
- 単体テストの生成
- バグの修正提案
- コミットメッセージの生成
- リファクタリングの支援
- デバッグの手助け

## 回答方針:
- 日本語で明確かつ簡潔に回答
- Markdownを使用して見やすく整理
- コードブロックは適切な言語を指定
- 実用的で具体的な提案を提供
- ユーザーの次のアクションを明示

## 出力形式:
- コードブロックに行番号は含めない
- 全体をバッククォートで囲まない
- 改行には `\n` ではなく実際の改行を使用
- 関連するコードのみを出力（不要なコードは含めない）

効率的で質の高いコード作成をサポートし、ユーザーの開発体験を向上させることが目標です。
]]
end

return {
  {
    'coder/claudecode.nvim',
    dependencies = { 'folke/snacks.nvim' },
    event = 'VeryLazy',
    opts = {
      port_range = { min = 10000, max = 65535 },
      auto_start = true,
      log_level = 'debug',
      track_selection = true,
      terminal = {
        split_side = 'right',
        split_width_percentage = 0.45,
        auto_close = false,
      },
      diff_opts = {
        auto_close_on_accept = true,
        vertical_split = true,
        open_in_current_tab = true,
        show_line_numbers = true,
      },
    },
    keys = {
      -- === CORE CLAUDE CODE FUNCTIONALITY ===
      { '<leader>cc', '<cmd>ClaudeCode<cr>', desc = 'Open/Toggle Claude Code' },
      { '<leader>cf', '<cmd>ClaudeCodeFocus<cr>', desc = 'Focus Claude Code' },

      -- === CONTEXT MANAGEMENT ===
      {
        '<leader>c+',
        function()
          add_file_with_context()
        end,
        desc = 'Add file with context',
      },
      {
        '<leader>cA',
        function()
          add_file_with_context()
          vim.cmd('ClaudeCodeFocus')
        end,
        desc = 'Add file and focus Claude',
      },

      -- === SELECTION & COMMUNICATION ===
      {
        '<leader>cv',
        function()
          local text = get_visual_selection()
          if text == '' or text == nil then
            vim.notify('No text selected', vim.log.levels.WARN)
            return
          end

          local prompt = string.format(
            [[
以下の選択されたコードについて分析してください：

**選択コード:**
```%s
%s
```

何かご質問やリクエストがあれば教えてください。
]],
            vim.bo.filetype or '',
            text
          )

          execute_prompt(prompt, true)
        end,
        mode = 'v',
        desc = 'Send selection to Claude',
      },
      {
        '<leader>ci',
        function()
          vim.cmd('ClaudeCodeFocus')
          vim.notify('Claude Code ready for input. Type your question directly.', vim.log.levels.INFO)
        end,
        desc = 'Interactive Claude session',
        mode = { 'n', 'v' },
      },

      -- === DIFF MANAGEMENT ===
      { '<leader>cd', '<cmd>ClaudeCodeDiffAccept<cr>', desc = 'Accept Claude diff' },
      { '<leader>cD', '<cmd>ClaudeCodeDiffDeny<cr>', desc = 'Reject Claude diff' },

      -- === COPILOT REPLACEMENT WORKFLOWS ===

      -- Code Review (replacing CopilotChatReview)
      {
        '<leader>cr',
        function()
          local prompt = get_japanese_system_prompt()
            .. [[

以下のコードを包括的にレビューしてください：

## レビュー観点
1. **コード品質・スタイル**
   - 命名規則と可読性
   - コード構造と整理
   - 言語固有の慣用句との一致

2. **パフォーマンス・効率性**
   - アルゴリズムの複雑度
   - メモリ使用量
   - 最適化の可能性

3. **セキュリティ・信頼性**
   - セキュリティ脆弱性
   - エラー処理
   - エッジケースの対応

4. **ベストプラクティス**
   - デザインパターン
   - テスト観点
   - 保守性

行番号を参照して具体的な改善提案をお願いします。]]

          send_enhanced_prompt(prompt, true)
        end,
        desc = '🔍 コードレビュー',
        mode = { 'n', 'v' },
      },

      -- Diagnostic Fixing (replacing CopilotChatFixDiagnostic)
      {
        '<leader>cx',
        function()
          local diag_context = get_diagnostic_context()
          local prompt = get_japanese_system_prompt()
            .. '\n\n'
            .. diag_context
            .. [[

上記の診断エラーを修正してください：

## 修正手順
1. エラーの根本原因を特定
2. 修正されたコードを提供
3. なぜエラーが発生したかを説明
4. 実際にコードを修正する
5. どこを修正したかを明確に示す

診断が表示されていない場合は、コードを分析して潜在的な問題を見つけて修正してください。]]

          send_enhanced_prompt(prompt, true)
        end,
        desc = '🔧 診断エラー修正',
      },

      -- Commit Message Generation (replacing CopilotChatCommitStaged)
      {
        '<leader>cm',
        function()
          local git_context = get_git_context()
          local prompt = get_japanese_system_prompt()
            .. '\n\n'
            .. git_context
            .. [[

以下の指針に従ってコミットメッセージを生成してください：

## フォーマット
**形式**: Conventional Commits (type: description)
**タイプ**: feat, fix, docs, style, refactor, test, chore
**説明**: 明確で簡潔、命令形
**長さ**: タイトル≤50文字、本文≤72文字/行

## 要求
- 変更内容を分析して適切なコミットメッセージを作成
- 日本語でも英語でも可（プロジェクトに合わせて選択）
- 変更の意図と影響を明確に示す]]

          send_enhanced_prompt(prompt, false)
        end,
        desc = '📝 コミットメッセージ生成',
      },

      -- Code Explanation (new feature)
      {
        '<leader>ce',
        function()
          local prompt = get_japanese_system_prompt()
            .. [[

このコードを詳しく説明してください：

## 説明項目
1. **目的**: このコードが達成すること
2. **ロジックフロー**: 実行の段階的な流れ
3. **主要コンポーネント**: 重要な関数、クラス、変数
4. **依存関係**: 外部ライブラリやフレームワーク
5. **複雑性**: 特に複雑で巧妙な部分
6. **使用法**: より大きなアプリケーションでの位置づけ

理解しやすく、かつ詳細な説明をお願いします。]]

          send_enhanced_prompt(prompt, true)
        end,
        desc = '📚 コード解説',
        mode = { 'n', 'v' },
      },

      -- Test Generation (new feature)
      {
        '<leader>ct',
        function()
          local prompt = get_japanese_system_prompt()
            .. [[

このコードの包括的な単体テストを生成してください：

## テスト要件
1. **テストフレームワーク**: この言語に適したフレームワークを使用
2. **カバレッジ**: 正常ケース、エッジケース、エラー条件
3. **構造**: 記述的な名前で整理されたテストスイート
4. **モック**: 外部依存関係を適切にモック
5. **アサーション**: 明確で意味のあるテストアサーション
6. **ドキュメント**: 複雑なテストシナリオの説明コメント

実行可能な完全なテストコードを提供してください。]]

          send_enhanced_prompt(prompt, true)
        end,
        desc = '🧪 テスト生成',
        mode = { 'n', 'v' },
      },

      -- Translation (migrated from CodeCompanion)
      {
        '<leader>ctr',
        function()
          translate_selection()
        end,
        mode = 'v',
        desc = '🌐 選択テキストを翻訳',
      },

      {
        '<leader>ctr',
        function()
          local prompt = get_japanese_system_prompt()
            .. [[

現在のファイルの内容またはコメントを翻訳してください：

## 翻訳方針
- 自動言語検出
- 日本語→英語、その他→日本語
- 自然で正確な表現
- 元の文脈とニュアンスを保持
- 必要に応じて文化的説明を追加
- 長いテキストは省略せず全文翻訳

翻訳対象を指定してください（コメント、ドキュメント、変数名など）]]

          send_enhanced_prompt(prompt, true)
        end,
        desc = '🌐 ファイル翻訳',
      },

      -- Code Optimization (new feature)
      {
        '<leader>co',
        function()
          local prompt = get_japanese_system_prompt()
            .. [[

このコードをパフォーマンスと保守性の観点から最適化してください：

## 最適化項目
1. **パフォーマンス**: 時間/空間計算量の改善
2. **可読性**: コードの明確性と構造の向上
3. **保守性**: 変更・拡張の容易さ
4. **言語慣用句**: 言語固有のベストプラクティス
5. **エラー処理**: 堅牢性の向上
6. **ドキュメント**: 必要な箇所にコメント追加

最適化されたコードと変更点の説明を提供してください。]]

          send_enhanced_prompt(prompt, true)
        end,
        desc = '⚡ コード最適化',
        mode = { 'n', 'v' },
      },

      -- === QUICK ACCESS WORKFLOWS ===
      {
        '<leader>cq',
        function()
          add_file_with_context()
          vim.cmd('ClaudeCodeFocus')
          vim.notify('Claude Code ready! Current file added to context.', vim.log.levels.INFO)
        end,
        desc = '🚀 クイック Claude（追加+フォーカス）',
      },

      -- Debug Helper
      {
        '<leader>cdb',
        function()
          local prompt = get_japanese_system_prompt()
            .. [[

このコードのデバッグを支援してください：

## デバッグ支援項目
1. **問題特定**: 何が間違っている可能性があるか
2. **デバッグ戦略**: どのようにデバッグにアプローチすべきか
3. **一般的な落とし穴**: この種のコードでの典型的な問題
4. **デバッグツール**: 役立つツールや技法
5. **テスト**: 修正が正しく動作することを確認する方法

具体的なデバッグ手順と提案を提供してください。]]

          send_enhanced_prompt(prompt, true)
        end,
        desc = '🐛 デバッグ支援',
        mode = { 'n', 'v' },
      },

      -- Refactoring Assistant
      {
        '<leader>crf',
        function()
          local prompt = get_japanese_system_prompt()
            .. [[

このコードのリファクタリングを支援してください：

## リファクタリング観点
1. **構造改善**: より良い整理とモジュール化
2. **デザインパターン**: 適切なデザインパターンの適用
3. **コード重複**: 抽象化による重複の排除
4. **命名**: 変数・関数名の改善
5. **関心の分離**: 責任の適切な分散
6. **後方互換性**: 既存インターフェースの可能な限りの維持

改善されたコードと改善点の説明を提供してください。]]

          send_enhanced_prompt(prompt, true)
        end,
        desc = '🔄 リファクタリング',
        mode = { 'n', 'v' },
      },

      -- Documentation Generator
      {
        '<leader>cdoc',
        function()
          local prompt = get_japanese_system_prompt()
            .. [[

このコードの包括的なドキュメントを生成してください：

## ドキュメント項目
1. **概要**: 機能の要約
2. **パラメータ**: 入力値の説明
3. **戻り値**: 出力の説明
4. **使用例**: 実際の使用方法
5. **注意事項**: 重要な制限や前提条件
6. **関連**: 関連する関数やクラス

適切なドキュメント形式（JSDoc、Rustdoc、Pythonドキュメントなど）で出力してください。]]

          send_enhanced_prompt(prompt, true)
        end,
        desc = '📖 ドキュメント生成',
        mode = { 'n', 'v' },
      },

      -- Performance Analysis
      {
        '<leader>cperf',
        function()
          local prompt = get_japanese_system_prompt()
            .. [[

このコードのパフォーマンス分析を行ってください：

## 分析項目
1. **時間計算量**: Big-O記法での評価
2. **空間計算量**: メモリ使用量の分析
3. **ボトルネック**: パフォーマンスの問題箇所
4. **最適化提案**: 具体的な改善方法
5. **プロファイリング**: 測定すべき指標
6. **スケーラビリティ**: 大量データでの動作

詳細な分析結果と改善提案を提供してください。]]

          send_enhanced_prompt(prompt, true)
        end,
        desc = '⏱️ パフォーマンス分析',
        mode = { 'n', 'v' },
      },
    },
  },
}
