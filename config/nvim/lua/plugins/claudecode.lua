-- Constants
local TEMP_DIR = vim.fn.stdpath('cache') .. '/claude_prompts'
local MAX_POPUP_WIDTH = 120
local MAX_POPUP_HEIGHT = 40
local MAX_DIFF_LINES = 50
local CACHE_TTL = 30 -- seconds

-- Cache for expensive operations
local cache = {
  git_context = { data = '', timestamp = 0 },
}

-- Utility functions
local utils = {
  create_temp_dir = function()
    local success, err = pcall(vim.fn.mkdir, TEMP_DIR, 'p')
    if not success then
      vim.notify('Failed to create temp directory: ' .. (err or 'unknown'), vim.log.levels.ERROR)
      return false
    end
    return true
  end,

  create_prompt_file = function(prompt_text)
    if not utils.create_temp_dir() then
      return nil
    end
    
    local temp_file = TEMP_DIR .. '/prompt_' .. os.time() .. '.md'
    local lines = {
      '# Claude Code Request',
      '',
      prompt_text,
      '',
      '---',
      '*This prompt was auto-generated. Edit as needed and send to Claude Code.*',
    }

    local success, err = pcall(vim.fn.writefile, lines, temp_file)
    if not success then
      vim.notify('Failed to create prompt file: ' .. (err or 'unknown'), vim.log.levels.ERROR)
      return nil
    end
    return temp_file
  end,

  safe_delete = function(file_path)
    if file_path and vim.fn.filereadable(file_path) == 1 then
      pcall(vim.fn.delete, file_path)
    end
  end,

  calculate_popup_size = function(text)
    local lines = vim.split(text, '\n')
    local max_width = 0
    for _, line in ipairs(lines) do
      max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
    end
    
    local width = math.min(max_width + 4, math.min(MAX_POPUP_WIDTH, vim.o.columns - 10))
    local height = math.min(#lines + 2, math.min(MAX_POPUP_HEIGHT, vim.o.lines - 10))
    
    return width, height
  end,

  is_cache_valid = function(cache_entry)
    return cache_entry.timestamp > 0 and 
           (os.time() - cache_entry.timestamp) < CACHE_TTL
  end,

  create_popup_window = function(response)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(response, '\n'))
    vim.bo[buf].filetype = 'markdown'
    vim.bo[buf].readonly = true

    local width, height = utils.calculate_popup_size(response)
    
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

    -- Set popup keymaps
    local opts = { buffer = buf, silent = true }
    vim.keymap.set('n', 'q', '<cmd>close<cr>', opts)
    vim.keymap.set('n', '<Esc>', '<cmd>close<cr>', opts)
    vim.keymap.set('n', '<CR>', '<cmd>close<cr>', opts)
    vim.keymap.set('n', 'y', function()
      vim.fn.setreg('+', response)
      vim.notify('✓ Copied to clipboard', vim.log.levels.INFO, { timeout = 1000 })
    end, opts)

    return win
  end,
}

-- Execute prompt using Claude CLI directly (faster than WebSocket)
local function execute_prompt(prompt_text, add_current_file)
  local temp_file = utils.create_prompt_file(prompt_text)
  if not temp_file then
    return
  end

  -- Build command with optional file context
  local cmd = 'claude -p'
  
  if add_current_file then
    local current_file = vim.fn.expand('%:p')
    local current_dir = vim.fn.expand('%:p:h')

    if current_file and current_file ~= '' then
      cmd = cmd .. ' --add-dir ' .. vim.fn.shellescape(current_dir)
      
      -- Enhance prompt with file content
      local file_content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
      local enhanced_prompt = string.format(
        'Current file: %s\n\nFile content:\n```%s\n%s\n```\n\n%s',
        current_file, vim.bo.filetype or '', file_content, prompt_text
      )

      utils.safe_delete(temp_file)
      temp_file = utils.create_prompt_file(enhanced_prompt)
      if not temp_file then
        return
      end
    end
  end

  cmd = cmd .. ' < ' .. vim.fn.shellescape(temp_file)

  vim.notify('Executing with Claude CLI...', vim.log.levels.INFO, {
    title = 'Claude Code',
    timeout = 1000,
  })

  -- Execute with improved error handling
  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data and #data > 0 then
        local response = table.concat(data, '\n')
        if response:match('%S') then
          utils.create_popup_window(response)
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
        if error_msg ~= '' then
          vim.notify('Claude CLI Error: ' .. error_msg, vim.log.levels.ERROR, {
            title = 'Claude Code Error',
            timeout = 5000,
          })
        end
      end
    end,
    on_exit = function(_, code)
      utils.safe_delete(temp_file)
      if code ~= 0 then
        vim.notify('Claude CLI exited with code: ' .. code, vim.log.levels.WARN, {
          title = 'Claude Code Warning',
          timeout = 3000,
        })
      end
    end,
  })
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

-- Git context gathering with caching
local function get_git_context()
  -- Return cached result if valid
  if utils.is_cache_valid(cache.git_context) then
    return cache.git_context.data
  end

  local git_status = vim.fn.systemlist('git status --porcelain 2>/dev/null')
  local git_diff = vim.fn.systemlist('git diff --cached 2>/dev/null')

  if vim.v.shell_error ~= 0 or #git_diff == 0 then
    git_diff = vim.fn.systemlist('git diff 2>/dev/null')
  end

  local context = ''

  if #git_status > 0 then
    context = context .. 'Changed files:\n' .. table.concat(git_status, '\n') .. '\n\n'
  end

  if #git_diff > 0 and #git_diff < MAX_DIFF_LINES then
    context = context .. 'Recent changes:\n```diff\n' .. table.concat(git_diff, '\n') .. '\n```\n\n'
  end

  -- Cache the result
  cache.git_context = {
    data = context,
    timestamp = os.time(),
  }

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

  if text == '' or text == nil then
    vim.notify('No text selected for translation.', vim.log.levels.WARN)
    return
  end

  local prompt = string.format(prompts.translation, text)
  execute_prompt(prompt, false)
end

-- Prompt templates for better maintainability
local prompts = {
  system = [[
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
]],

  translation = [[
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

  selection_analysis = [[
以下の選択されたコードについて分析してください：

**選択コード:**
```%s
%s
```

何かご質問やリクエストがあれば教えてください。
]],

  code_review = [[

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

行番号を参照して具体的な改善提案をお願いします。]],

  diagnostic_fix = [[

上記の診断エラーを修正してください：

**ファイル**: %s

## 修正指示
1. エラーの根本原因を特定
2. **実際にファイルを編集して修正する**
3. なぜエラーが発生したかを説明
4. どこを修正したかを明確に示す

**重要**: 
- 単なる提案ではなく、実際にファイルを編集してエラーを修正してください
- Edit ツールを使用してファイルの該当箇所を直接修正してください
- 既存のコードスタイルと構造を維持してください

診断が表示されていない場合は、コードを分析して潜在的な問題を見つけて修正してください。]],

  commit_message = [[

以下の指針に従ってコミットメッセージを生成してください：

## フォーマット
**形式**: Conventional Commits (type: description)
**タイプ**: feat, fix, docs, style, refactor, test, chore
**説明**: 明確で簡潔、命令形
**長さ**: タイトル≤50文字、本文≤72文字/行

## 要求
- 変更内容を分析して適切なコミットメッセージを作成
- 日本語でも英語でも可（プロジェクトに合わせて選択）
- 変更の意図と影響を明確に示す]],

  code_explanation = [[

このコードを詳しく説明してください：

## 説明項目
1. **目的**: このコードが達成すること
2. **ロジックフロー**: 実行の段階的な流れ
3. **主要コンポーネント**: 重要な関数、クラス、変数
4. **依存関係**: 外部ライブラリやフレームワーク
5. **複雑性**: 特に複雑で巧妙な部分
6. **使用法**: より大きなアプリケーションでの位置づけ

理解しやすく、かつ詳細な説明をお願いします。]],

  test_generation = [[

このコードの包括的な単体テストを生成してください：

## テスト要件
1. **テストフレームワーク**: この言語に適したフレームワークを使用
2. **カバレッジ**: 正常ケース、エッジケース、エラー条件
3. **構造**: 記述的な名前で整理されたテストスイート
4. **モック**: 外部依存関係を適切にモック
5. **アサーション**: 明確で意味のあるテストアサーション
6. **ドキュメント**: 複雑なテストシナリオの説明コメント

実行可能な完全なテストコードを提供してください。]],

  code_optimization = [[

このコードをパフォーマンスと保守性の観点から最適化してください：

## 最適化項目
1. **パフォーマンス**: 時間/空間計算量の改善
2. **可読性**: コードの明確性と構造の向上
3. **保守性**: 変更・拡張の容易さ
4. **言語慣用句**: 言語固有のベストプラクティス
5. **エラー処理**: 堅牢性の向上
6. **ドキュメント**: 必要な箇所にコメント追加

最適化されたコードと変更点の説明を提供してください。]],
}

-- Helper function to get system prompt with additional content
local function get_enhanced_prompt(template_key, ...)
  local template = prompts[template_key]
  if not template then
    vim.notify('Unknown prompt template: ' .. template_key, vim.log.levels.ERROR)
    return prompts.system
  end
  
  if template_key == 'system' then
    return template
  end
  
  -- For other templates, prepend system prompt
  if ... then
    return prompts.system .. string.format(template, ...)
  else
    return prompts.system .. template
  end
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

          local prompt = get_enhanced_prompt('selection_analysis', vim.bo.filetype or '', text)
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
          local prompt = get_enhanced_prompt('code_review')
          execute_prompt(prompt, true)
        end,
        desc = '🔍 コードレビュー',
        mode = { 'n', 'v' },
      },

      -- Diagnostic Fixing (replacing CopilotChatFixDiagnostic)
      {
        '<leader>cx',
        function()
          local diag_context = get_diagnostic_context()
          local current_file = vim.fn.expand('%:p')
          local prompt = prompts.system .. '\n\n' .. diag_context .. 
                        string.format(prompts.diagnostic_fix, current_file)
          execute_prompt(prompt, true)
        end,
        desc = '🔧 診断エラー修正',
      },

      -- Auto-fix diagnostic errors with LSP
      {
        '<leader>cxf',
        function()
          -- Try LSP code actions first
          vim.lsp.buf.code_action({
            filter = function(action)
              return action.kind and action.kind:match('quickfix')
            end,
            apply = true,
          })
          
          -- If no LSP actions available, use Claude
          vim.defer_fn(function()
            local diagnostics = vim.diagnostic.get(0, { lnum = vim.fn.line('.') - 1 })
            if #diagnostics > 0 then
              local diag_context = get_diagnostic_context()
              local current_file = vim.fn.expand('%:p')
              local prompt = get_japanese_system_prompt()
                .. '\n\n'
                .. diag_context
                .. string.format([[

このエラーを自動修正してください：

**ファイル**: %s

**要求事項**:
1. **実際にファイルを直接編集して修正する**
2. Edit ツールを使用してファイルの該当箇所を修正
3. 修正理由を簡潔に説明
4. 既存のコードスタイルを維持
5. 副作用を最小限に抑制

単なる提案ではなく、実際にファイルを修正してください。]], current_file)

              send_enhanced_prompt(prompt, true)
            end
          end, 500)
        end,
        desc = '🚀 自動診断修正',
      },

      -- Commit Message Generation (replacing CopilotChatCommitStaged)
      {
        '<leader>cm',
        function()
          local git_context = get_git_context()
          local prompt = prompts.system .. '\n\n' .. git_context .. prompts.commit_message
          execute_prompt(prompt, false)
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
          local prompt = get_enhanced_prompt('code_optimization')
          execute_prompt(prompt, true)
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
