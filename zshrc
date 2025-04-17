# @see https://scriptingosx.com/2019/06/moving-to-zsh/

export PATH="/usr/local/bin:/usr/local/sbin:/opt/homebrew/bin:$PATH"
export PATH="$PATH:/Users/brenna.martenson/Library/Python/3.9/bin"
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
function set_git_aliases() {
  if [ -d .git ] || git rev-parse --is-inside-work-tree &>/dev/null; then
     # alias files=":Git diff --name-only origin/main" TODO: Add this to zshenv or something?
     alias gac="git add . && git commit -m"
     alias gc="git checkout"
     alias gcb="git checkout -b"
     alias glo="git log --oneline"
     alias gs="git switch"
     # alias lines=":Git diff origin/main"
     alias main="git checkout main && git pull origin main"
     alias pull="git pull origin $(git rev-parse --abbrev-ref HEAD)"
     alias push="git push origin $(git rev-parse --abbrev-ref HEAD)"
     alias force="git push origin $(git rev-parse --abbrev-ref HEAD) -f"
     alias yolo="git push origin main"
else 
    # unalias files 2>/dev/null
    unalias gac 2>/dev/null
    unalias gc 2>/dev/null
    unalias gcb 2>/dev/null
    unalias glo 2>/dev/null
    unalias gs 2>/dev/null
    # unalias lines 2>/dev/null
    unalias main 2>/dev/null
    unalias pull 2>/dev/null
    unalias push 2>/dev/null
    unalias yolo 2>/dev/null
 fi
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd set_git_aliases
set_git_aliases

# Processes
alias killem="kill -9"
alias pxport="lsof -i :3000"
alias pxgit="ps aux | grep git"

# Devving
alias awsso="aws sso login"
alias go="npm run start"
alias goLocal="npm run start:local"
alias chex="npm run typecheck && npm run lint && npm run prettier-check"
alias nupgradez="npx npm-check-updates"
alias spec_="npx jest src/components/flowBuilder"
alias up="docker compose up"
alias vv="nvim"
alias yupgradez="yarn upgrade-interactive --latest"
alias neovim-something="/Users/brenna.martenson/.config/dotfiles/nvim"
alias nvim-test='NVIM_APPNAME="nvim-test" nvim'

# For Postscript
echo "{ \"credsStore\": \"ecr-login\" }" > ~/.docker/config.json

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
[ -s "$NVM_DIR/nvm.sh" ] && [ -f "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && [ -f "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"


