eval "$(/opt/homebrew/bin/brew shellenv)"
export ZPLUG_HOME=/opt/homebrew/opt/zplug
source $ZPLUG_HOME/init.zsh

## Basic Alias
alias vi='nvim'
alias ls='eza'
alias cat='bat'
alias grep='rg'
alias find='fd'
alias sed='gsed'
alias time='gtime'
alias la='ls -la'

# ----------------------------------------
# プラグイン
# ----------------------------------------
# 自動補完と提案を行うプラグイン（Gitの補完も強化）
zplug "zsh-users/zsh-autosuggestions"

# Zshの高機能補完を提供
zplug "zsh-users/zsh-completions"

# Zshのシンタックスハイライト（コマンドの色付け）
zplug "zsh-users/zsh-syntax-highlighting"

# Gitのステータス表示を強化するプラグイン
zplug "olivierverdier/zsh-git-prompt"

zplug "zsh-users/zsh-history-substring-search"  # 履歴のサブストリング検索

# 256色表示にする
zplug "chrissicool/zsh-256color"

if ! zplug check --verbose; then
    printf "Install? [y/N]: "
    if read -q; then
        echo; zplug install
    fi
fi
zplug load

# ----------------------------------------
# options
# ----------------------------------------
export AWS_PAGER=""
bindkey '^P' history-search-backward
bindkey '^N' history-search-forward

if [ -e /opt/homebrew/opt/zsh-completions ]; then
  fpath=(/opt/homebrew/opt/zsh-completions $fpath)
fi

# edit-command
autoload -z edit-command-line
zle -N edit-command-line
bindkey "^E" edit-command-line

# ----------------------------------------
# 補完の設定
# ----------------------------------------
#
# メニュー補完の設定
zstyle ':completion:*' menu select
# 補完リストの色付けを追加
zstyle ':completion:*:default' list-colors 'di=34:ln=36:so=35:pi=33:ex=31:bd=34;01:cd=33;01:su=37;01:sg=30;01:tw=30;42:ow=30;43'

# Gitのブランチやタグを補完
zstyle ':completion:*:*:git:*' users ${${(f)"$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes refs/tags)"}}
zstyle ':completion:*:*:git-checkout:*' tag-order 'refs/heads' 'refs/tags'

# 上位ディレクトリを優先的に補完
zstyle ':completion:*:*:(|cd|pushd|rmdir):*' sort 'true'

# ワイルドカード補完の設定（サブストリング検索の補完強化）
setopt NO_CASE_GLOB  #グロブで大文字小文字を区別しない
setopt CORRECT  #コマンドのスペルをチェックして修正候補を表示
setopt CORRECT_ALL  #コマンドラインのすべての引数のスペルをチェックして修正候補を表示
setopt hist_ignore_dups #連続する同じコマンドをヒストリに追加しない
# 部分一致でのファイル名補完を有効にする
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z} r:|[._-]=* r:|=*' 'm:{a-z}={A-Z} r:|=*' 'l:|=* r:|=*'
# Tabを押したときに補完候補を表示する
zstyle ':completion:*' select-prompt '%SScrolling active: current selection at line %L, current query at line %i, selection completed at line %k%e. List longer than %p%%. Abort and select at line %K%e.'

# compinitの実行（補完システムを初期化）
autoload -Uz compinit
compinit -u

# タブキーの動作確認
bindkey '^I' expand-or-complete
#
# ----------------------------------------
# Functions
# ----------------------------------------
#
function fe() {
  local files
  IFS=$'\n' files=($(fzf --preview "head -100 {}" --query="$1" --multi --select-1 --exit-0))
  echo "${files[@]}"
  [[ -n "$files" ]] && ${EDITOR:-nvim} "${files[@]}"
}

c () {
    if [ $# -gt 0 ]; then
        \cd "$@"
        return
    fi
    local gitroot=`git rev-parse --show-toplevel 2>/dev/null`
    if [ ! "$gitroot" = "" ]; then
        \cd "$gitroot"
        return
    fi
    \cd
}

# ----------------------------------------
# Other
# ----------------------------------------

alias ip="curl ifconfig.me"
alias tarbreak='tar -zxvf'
alias relogin='exec $SHELL -l'

# fzf
source <(fzf --zsh)
export FZF_ALT_C_OPTS="--select-1 --exit-0"
export FZF_DEFAULT_OPTS="--layout=reverse"

alias g='cd $(ghq root)/$(ghq list | fzf --preview "bat --color=always --style=header,grid --line-range :80 $(ghq root)/{}/README.*" --preview-window=right:50%)'
alias gu='ghq list smartmat| ghq get --update --parallel'
alias ghroot='cd $(ghq root)/github.com'
alias gitclean='git branch --merged|egrep -v "\*|develop|master"|xargs git branch -d && git fetch --prune'
alias dgc='docker system prune'
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion

eval "$(starship init zsh)"
# ----------------------------------------
# Local Specific Configuration
# ----------------------------------------

if [ -f ~/.zshrc.local ]; then
    source ~/.zshrc.local
fi

export PATH="/opt/homebrew/opt/curl/bin:$PATH"
eval "$(starship init zsh)"
