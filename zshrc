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
alias la="ls -lA"
alias ll="ls -l"
alias ls="ls -G"
alias mv="mv -i"
alias reload="source ~/.zprofile && cd ../ && cd -"

# Moving Around
alias ..="cd ../"
alias ...="cd ../../"
alias ....="cd ../../../"
alias dotfiles="cd ~/dotfiles"
alias fe="cd ~/Projects/postscript/postscript-frontend"
alias api="cd ~/Projects/postscript/postscript-api"

# Gits
alias gac="git add . && git commit -m"
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
alias awsso="aws sso login"
alias dev="pnpm dev:web"
alias go="npm run start"
alias local="npm run start:local"
alias nupgradez="npx npm-check-updates"
alias pp="pnpm"
alias up="docker compose up"
alias vv="nvim"
alias yupgradez="yarn upgrade-interactive --latest"

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

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
