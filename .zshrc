export LANG=ja_JP.UTF-8
# Source Prezto.
if [[ -s "${ZDOTDIR:-$HOME}/.zprezto/init.zsh" ]]; then
  source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"
fi

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Customize to your needs...
unset GOPATH
unset GOROOT
export AWS_PAGER=""
export BASE_DIR=~/go
export EDITOR=nvim
export VISUAL=nvim

export PATH="$(go env GOPATH)/bin:$PATH"
eval "$(direnv hook zsh)"

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
export FZF_ALT_C_OPTS="--select-1 --exit-0"
export FZF_DEFAULT_OPTS="--layout=reverse"

if [ -e ~/.zsh/completions ]; then
  fpath=(~/.zsh/completions $fpath)
fi

function precmd() {
  if [ ! -z $TMUX ]; then
    tmux refresh-client -S
  fi
}
setopt share_history
bindkey '^P' history-beginning-search-backward
bindkey '^N' history-beginning-search-forward
autoload -U compinit
compinit

# edit-command
autoload -z edit-command-line
zle -N edit-command-line
bindkey "^E" edit-command-line

alias ip="curl ifconfig.me"

if [[ -f "$HOME/Documents/secret-dots/secret.zsh" ]]; then
    source "$HOME/Documents/secret-dots/secret.zsh"
fi

alias history='history 0'
alias ms='pmset sleepnow'
alias tarbreak='tar -zxvf'
alias m='memo'

alias relogin='exec $SHELL -l'

function fe() {
  local files
  IFS=$'\n' files=($(fzf --preview "head -100 {}" --query="$1" --multi --select-1 --exit-0))
  echo "${files[@]}"
  [[ -n "$files" ]] && ${EDITOR:-nvim} "${files[@]}"
}

alias g='cd $(ghq root)/$(ghq list | fzf --preview "bat --color=always --style=header,grid --line-range :80 $(ghq root)/{}/README.*" --preview-window=right:50%)'
alias gu='ghq list smartmat| ghq get --update --parallel'
alias ghroot='cd $(ghq root)/github.com'

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

alias gitclean='git branch --merged|egrep -v "\*|develop|master"|xargs git branch -d && git fetch --prune'
alias time='gtime -f %E'
alias dgc='docker system prune'
alias vi='/usr/local/bin/nvim'

export PATH="$HOME/.local/share/aquaproj-aqua/bin:$PATH"

source <(kubectl completion zsh)

# worktree移動
function cw() {
    # カレントディレクトリがGitリポジトリ上かどうか
    git rev-parse &>/dev/null
    if [ $? -ne 0 ]; then
        echo fatal: Not a git repository.
        return
    fi

    local selectedWorkTreeDir=`git worktree list | fzf | awk '{print $1}'`

    if [ "$selectedWorkTreeDir" = "" ]; then
        # Ctrl-C.
        return
    fi

    cd ${selectedWorkTreeDir}
}

function vim-startuptime-detail() {
  local time_file
  time_file=$(mktemp -t "_vim_startuptime")
  echo "output: $time_file"
  time vi -c ":q " --startuptime $time_file
  tail -n 1 $time_file | cut -d " " -f1 | tr -d "\n" && echo " [ms]\n"
  cat $time_file | sort -n -k 2 | tail -n 20
}

export DOCKER_BUILDKIT=1
export PATH="${PATH}:${HOME}/.krew/bin"
export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"
