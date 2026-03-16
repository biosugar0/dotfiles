#!/bin/bash
# PreToolUse hook: Block editing linter/formatter config files
# Prevents agent from silencing lint errors by modifying config instead of fixing code

input=$(cat)

file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[ -z "$file_path" ] && exit 0

basename=$(basename "$file_path")

# Protected config file patterns
case "$basename" in
  .eslintrc|.eslintrc.*|eslint.config.*) ;;
  biome.json|biome.jsonc) ;;
  .prettierrc|.prettierrc.*|prettier.config.*) ;;
  tsconfig.json|tsconfig.*.json) ;;
  jest.config.*|vitest.config.*) ;;
  .golangci.yml|.golangci.yaml) ;;
  .swiftlint.yml) ;;
  .pre-commit-config.yaml) ;;
  lefthook.yml|lefthook-local.yml) ;;
  mypy.ini|.mypy.ini) ;;
  .ruff.toml|ruff.toml) ;;
  *) exit 0 ;;
esac

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "リンター/フォーマッター設定ファイルの編集はブロックされた。設定を変更するのではなく、コードを修正してください。"
  }
}'
