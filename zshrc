# @see https://scriptingosx.com/2019/06/moving-to-zsh/

export PATH="/usr/local/bin:/usr/local/sbin:/opt/homebrew/bin:$PATH"
export EDITOR="nvim"

# Add color to man pages
export LESS_TERMCAP_md="$(tput setaf 4)"
# http://zsh.sourceforge.net/Doc/Release/Options.html
setopt APPEND_HISTORY
setopt AUTO_CD
setopt GLOB_COMPLETE
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt INC_APPEND_HISTORY
setopt NO_CASE_GLOB
setopt SHARE_HISTORY
# TODO: Need to find equivalent of Readline's `set history-preserve-point`

# @see http://zsh.sourceforge.net/Doc/Release/Parameters.html
HISTFILE=${ZDOTDIR:-$HOME}/.zsh_history
HISTSIZE=500
SAVEHIST=500

# @see http://zsh.sourceforge.net/Doc/Release/Zsh-Line-Editor.html
bindkey '^P' history-incremental-pattern-search-backward
bindkey '^N' history-incremental-pattern-search-forward

# @see http://zsh.sourceforge.net/Doc/Release/Prompt-Expansion.html
# @see https://github.com/git/git/blob/master/contrib/completion/git-prompt.sh
if [ -f $(brew --prefix)/etc/bash_completion.d/git-prompt.sh ]; then
  . $(brew --prefix)/etc/bash_completion.d/git-prompt.sh
  setopt PROMPT_SUBST
  GIT_PS1_SHOWDIRTYSTATE="true"
  # PROMPT='%F{5}[%m]%f %F{4}%1~%f %F{6}$(__git_ps1 "[%s] ")%f%F{8}%#%f '
  PROMPT='%F{51}[%n]%f %F{197}%1~%f %F{208}$(__git_ps1 "[%s] ⚡ ")%f%F{8}%#%f '
else
  PROMPT='%F{51}[%n]%f %F{197}%1~%f %F{6}%#%f ⚡ '
fi

# Handy stuff

# Basic
alias cp="cp -i"
alias dev="pnpm dev:web"
alias la="ls -lA"
alias ll="ls -l"
alias ls="ls -G"
alias mv="mv -i"
alias reload="source ~/.zprofile && cd ../ && cd -"

# Moving Around
alias ..="cd ../"
alias ...="cd ../../"
alias ....="cd ../../../"
alias balance="cd ~/Repositories/balance"
alias dotfiles="cd ~/dotfiles"
alias oog="cd ~/Repositories/vangst/oogmerk"
alias pikl="cd ~/Repositories/pikl-repos/pikl"

# Gits
alias gf="git clean -f"
alias gfd="git clean -f -d"
alias glo="git log --oneline"
alias main="git checkout main && git pull origin main"
alias yolo="git push origin main"

# Processes
alias killem="kill -9"
alias pxport="lsof -i :3000"
alias pxgit="ps aux | grep git"

# Devving
alias pp="pnpm"
alias vv="nvim"

# case insensitive path-completion
zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' \
                                    'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*' \
                                    'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*' \
                                    'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*'

# partial completion suggestions
zstyle ':completion:*' list-suffixes
zstyle ':completion:*' expand prefix suffix

# Load zsh completion engine
autoload -Uz compinit && compinit
true
