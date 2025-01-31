return {
  name = 'weather_tool',
  cmds = {
    ---@param self CodeCompanion.Tools
    ---@param input any
    function(self, input)
      -- ここにハードコーディングした天気情報を仕込む
      print('Weather Tool: Executing...')
      local today_weather = '東京は晴れ、最高気温20度、最低気温10度です。'
      vim.notify('[Weather Tool] Today: ' .. today_weather)

      -- status = 'success' と msg フィールドが必須
      return {
        status = 'success',
        msg = today_weather,
      }
    end,
  },

  -- XML スキーマ (LLMがこのツールを呼び出す際、どういう形で呼ぶか)
  schema = {
    {
      tool = {
        _attr = { name = 'weather_tool' },
        action = {
          _attr = { type = 'fetch_weather' },
          location = '<![CDATA[Tokyo]]>',
        },
      },
    },
  },

  -- システムプロンプト (LLM にこのツールの目的や XML の書き方を教える)
  system_prompt = function(schema)
    print(vim.inspect(schema[1]))
    print('Weather Tool: system_prompt...')
    local xml2lua = require('codecompanion.utils.xml.xml2lua')
    return string.format(
      [[
### Weather Tool

1. **Purpose**: Provide today's weather information.
2. **Usage**: To call this tool, you **must** return an XML block inside triple backticks, following the exact structure below.
3. **Important**:
   - The XML **must** start with `<tool name="weather_tool">`.
   - The `<action>` tag **must** contain a `type="fetch_weather"` attribute.
   - The `<location>` tag **must** be inside `<action>`.
   - Do **not** modify the structure.
   - **Example of correct XML format:**

```xml
%s
```

]],
      xml2lua.toXml({ tools = { schema[1] } })
    )
  end,

  output = {
    success = function(self, cmd, stdout)
      if type(stdout) == 'table' then
        stdout = table.concat(stdout, '\n')
      end
      local config = require('codecompanion.config')
      self.chat:add_buf_message({
        role = config.constants.USER_ROLE,
        content = string.format('✅ Weather tool executed successfully!\n\n今日の天気: %s', stdout),
      })
    end,
    error = function(self, cmd, stderr)
      local config = require('codecompanion.config')
      local log = require('codecompanion.utils.log')
      log:error('[Weather Tool] error() => %s', vim.inspect(stderr))
      config.chat:add_buf_message({
        role = config.constants.USER_ROLE,
        content = string.format('❌ Weather tool encountered an error!\n\nError: %s', stderr),
      })
    end,
  },
}
