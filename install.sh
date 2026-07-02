#!/usr/bin/env bash
set -euo pipefail

echo "=== dotfiles installer (chezmoi) ==="

# Homebrew
if ! command -v brew &>/dev/null; then
	echo "Installing Homebrew..."
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

# Brewfile
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "$SCRIPT_DIR/Brewfile" ]]; then
	echo "Installing packages from Brewfile..."
	brew bundle --file="$SCRIPT_DIR/Brewfile"
fi

# chezmoi
if ! command -v chezmoi &>/dev/null; then
	echo "Installing chezmoi..."
	brew install chezmoi
fi

# git-wt (git worktree manager)
if command -v go &>/dev/null; then
	if ! command -v git-wt &>/dev/null; then
		echo "Installing git-wt..."
		go install github.com/k1LoW/git-wt@latest
	fi
fi

# Apply dotfiles
echo "Applying dotfiles with chezmoi..."
chezmoi init --source "$SCRIPT_DIR" --apply

# tmux plugins (tpm)
if [[ ! -d "$HOME/.config/tmux/plugins/tpm" ]]; then
	echo "Installing tmux plugin manager..."
	git clone https://github.com/tmux-plugins/tpm "$HOME/.config/tmux/plugins/tpm"
fi

# Herdr integrations (agent の session/state 報告 hook を配置する)
# claude: ~/.config/claude/hooks/herdr-agent-state.sh (installer 管理、chezmoi 非管理)
#         settings.json への hook 登録は settings.json.tmpl 側に同一文字列で定義済み
# codex:  ~/.codex/herdr-agent-state.sh
if command -v herdr &>/dev/null; then
	echo "Installing herdr integrations..."
	# CLAUDE_CONFIG_DIR 未設定の clean env では installer が ~/.claude 側に hook を
	# 置き、settings.json.tmpl の参照先 (~/.config/claude) と食い違って SessionStart
	# hook が exit 127 で壊れるため、明示的に揃える
	CLAUDE_CONFIG_DIR="$HOME/.config/claude" herdr integration install claude || true
	if command -v codex &>/dev/null; then
		herdr integration install codex || true
	fi
	# 公式 agent skill は AGPL のため repo に vendor せず、インストール時に取得する
	mkdir -p "$HOME/.config/claude/skills/herdr"
	curl -fsSL https://raw.githubusercontent.com/ogulcancelik/herdr/master/SKILL.md \
		-o "$HOME/.config/claude/skills/herdr/SKILL.md" ||
		echo "note: herdr SKILL.md download failed (retry: install.sh or fetch manually)"
	# worktree-setup plugin (worktree.created イベントで wt.copy/wt.hook を適用)
	# plugin registry は server 側 state のため、server 未起動だと失敗する
	if ! herdr plugin link "$HOME/.config/herdr/plugins/worktree-setup" >/dev/null 2>&1; then
		echo "note: herdr server not running. After starting herdr, run:"
		echo "  herdr plugin link ~/.config/herdr/plugins/worktree-setup"
	fi
fi


# playwright-ext-token
DOTFILES_DIR="$HOME/ghq/github.com/biosugar0/dotfiles"
mkdir -p "$HOME/.local/bin"
ln -sf "$DOTFILES_DIR/bin/playwright-ext-token" "$HOME/.local/bin/playwright-ext-token"

# editprompt (CLI tool for writing prompts in editor)
if command -v npm &>/dev/null; then
	if ! command -v editprompt &>/dev/null; then
		echo "Installing editprompt..."
		npm install -g editprompt
	fi
fi

# AWS Session Manager Plugin (install without sudo)
if ! command -v session-manager-plugin &>/dev/null; then
	echo "Installing AWS Session Manager Plugin..."
	mkdir -p "$HOME/.local/bin"
	TMPDIR=$(mktemp -d)
	curl -sL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/sessionmanager-bundle.zip" -o "$TMPDIR/sessionmanager-bundle.zip"
	unzip -q "$TMPDIR/sessionmanager-bundle.zip" -d "$TMPDIR"
	"$TMPDIR/sessionmanager-bundle/install" -i "$HOME/.local/sessionmanagerplugin" -b "$HOME/.local/bin/session-manager-plugin"
	rm -rf "$TMPDIR"
fi

echo "=== Done! ==="
echo "Run 'exec zsh' to reload shell"
echo "Run 'prefix + I' in tmux to install plugins"
