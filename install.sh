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

# Apply dotfiles
echo "Applying dotfiles with chezmoi..."
chezmoi init --source "$SCRIPT_DIR" --apply

# tmux plugins (tpm)
if [[ ! -d "$HOME/.config/tmux/plugins/tpm" ]]; then
	echo "Installing tmux plugin manager..."
	git clone https://github.com/tmux-plugins/tpm "$HOME/.config/tmux/plugins/tpm"
fi

# git-worktree-runner (git gtr)
if command -v ghq &>/dev/null; then
	if [[ ! -d "$HOME/ghq/github.com/coderabbitai/git-worktree-runner" ]]; then
		echo "Installing git-worktree-runner..."
		ghq get coderabbitai/git-worktree-runner
	fi
	mkdir -p "$HOME/.local/bin"
	ln -sf "$HOME/ghq/github.com/coderabbitai/git-worktree-runner/bin/git-gtr" "$HOME/.local/bin/git-gtr"
fi

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
