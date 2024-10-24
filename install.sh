#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
echo "SCRIPT_DIR: $SCRIPT_DIR"

# スクリプト中で使われるPATHを予め通しておく
PATH="$PATH:/opt/homebrew/bin"

# ディレクトリのsymlinkを作る
function symlink_dir() {
    src=$1
    dst=$2
    [[ -L "$dst" ]] && rm -f "$dst"  # リンクがある場合に削除する
    ln -sf "$src" "$dst"
}

## Homebrewのインストール
if ! command -v brew >/dev/null 2>&1; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Brewfileを使用してHomebrewのパッケージを冪等にインストール
if [[ -f "$SCRIPT_DIR/Brewfile" ]]; then
    brew bundle --file="$SCRIPT_DIR/Brewfile"
else
    echo "Brewfile not found in $SCRIPT_DIR"
    exit 1
fi

# configディレクトリを作成し、設定ファイルをsymlinkする
mkdir -p $HOME/.config/

# .config/zshでzshの設定を管理するため、ZDOTDIRを指定する
new_content="ZDOTDIR=\$HOME/.config/zsh"
# /etc/zshenv に追記する
echo "$new_content" | sudo tee /etc/zshenv > /dev/null
# 成功メッセージの表示
if [[ $? -eq 0 ]]; then
  echo "/etc/zshenv was successfully updated."
else
  echo "Failed to update /etc/zshenv."
fi

# シンボリックリンクの作成
symlink_dir $SCRIPT_DIR/config/zsh $HOME/.config/zsh
symlink_dir $SCRIPT_DIR/config/git $HOME/.config/git
symlink_dir $SCRIPT_DIR/config/tmux $HOME/.config/tmux
symlink_dir $SCRIPT_DIR/config/nvim $HOME/.config/nvim
symlink_dir $SCRIPT_DIR/config/wezterm $HOME/.config/wezterm
symlink_dir $SCRIPT_DIR/config/starship.toml $HOME/.config/starship.toml
