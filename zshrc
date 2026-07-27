# Initialize Homebrew (hardcoded for Apple Silicon)
export HOMEBREW_PREFIX="/opt/homebrew"
export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
export HOMEBREW_REPOSITORY="/opt/homebrew"
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.local/bin:/usr/local/bin:/usr/local/sbin:$PATH"
export MANPATH="/opt/homebrew/share/man${MANPATH+:$MANPATH}:"
export INFOPATH="/opt/homebrew/share/info${INFOPATH+:$INFOPATH}"
export EDITOR="nvim"

# http://zsh.sourceforge.net/Doc/Release/Options.html
setopt AUTO_CD
setopt GLOB_COMPLETE
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt NO_CASE_GLOB
setopt SHARE_HISTORY

# @see http://zsh.sourceforge.net/Doc/Release/Parameters.html
HISTFILE=${ZDOTDIR:-$HOME}/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

# @see http://zsh.sourceforge.net/Doc/Release/Zsh-Line-Editor.html
bindkey '^P' history-incremental-pattern-search-backward
bindkey '^N' history-incremental-pattern-search-forward

# @see http://zsh.sourceforge.net/Doc/Release/Prompt-Expansion.html
# @see https://github.com/git/git/blob/master/contrib/completion/git-prompt.sh
if [ -f /opt/homebrew/etc/bash_completion.d/git-prompt.sh ]; then
  . /opt/homebrew/etc/bash_completion.d/git-prompt.sh
  setopt PROMPT_SUBST
  GIT_PS1_SHOWDIRTYSTATE="true"
  PROMPT='%F{5}[%n]%f %F{4}%1~%f %F{6}$(__git_ps1 "[%s] ")%f%F{8}%#%f '
else
  PROMPT='%F{5}[%n]%f %F{4}%1~%f %F{8}%#%f '
fi

# Handy stuff
alias ...="cd ../../"
alias ....="cd ../../../"
# alias bake="caffeinate -i -d -t 3600" # See Brenna's Additions at the end
alias cp="cp -i"
alias la="ls -lA"
alias ll="ls -l"
alias ls="ls -G"
alias mv="mv -i"
alias reload="source ~/.zshrc && cd ../ && cd -"


# case insensitive path-completion
zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' \
                                    'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*'

# partial completion suggestions
zstyle ':completion:*' list-suffixes
zstyle ':completion:*' expand prefix suffix

# Load zsh completion engine
autoload -Uz compinit && compinit

# pnpm
export PNPM_HOME="/Users/brenna.martenson@homebot.ai/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PNPM_HOME/bin:$PATH" ;;
esac
# pnpm end

# mise (version manager) — activates per-directory tool versions
if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi

# Machine-local overrides and secrets — not tracked in the dotfiles repo.
if [ -f "${ZDOTDIR:-$HOME}/.zshrc.local" ]; then
  source "${ZDOTDIR:-$HOME}/.zshrc.local"
fi

# ------------ Brenna's Additions -----------------------------
# &! backgrounds and disowns the caffeinate job atomically. A bare `disown`
# targets the shell's *current* job — which is whatever is suspended (e.g. a
# Ctrl-Z'd claude session), orphaning it beyond any future `fg`.
alias bake='caffeinate -i -d -t 3600 &! echo '\''Baking for 1 hour'\'
alias bbake='caffeinate -i -d -t 28800 &! echo '\''Baking for 8 hours'\'
alias bots="cd ~/Sites/homebotapp/surfaces-bots"
alias dotfiles="cd ~/dotfiles"
alias fe="cd ~/Sites/homebotapp/surfaces"
alias fpush="git push --force-with-lease origin"
alias giles="cd ~/Sites/martensonbj/giles"
alias gco="git checkout"
alias glo="git log --oneline"
alias main="git checkout main && git pull origin main"
alias nv="nvim"
alias ppb="pnpm build"
alias ppc="pnpm check"
alias ppd="pnpm dev"
alias recommit="git commit --amend --no-edit"
alias thaw='pkill caffeinate && echo '\''Thawed'\'' || echo '\''Nothing to thaw'\'
alias qa="cd ~/Sites/homebotapp/surfaces-reviews"

# ------------ Functions --------------------------------------

# daynight — flip macOS appearance (Ghostty follows via `light:beamish,dark:nordish`).
# Usage: `daynight` to toggle, `daynight light` or `daynight dark` to force.
daynight() {
  local action
  case "$1" in
    light) action='set dark mode to false' ;;
    dark)  action='set dark mode to true' ;;
    "")    action='set dark mode to not dark mode' ;;
    *)     print -u2 "usage: daynight [light|dark]"; return 1 ;;
  esac

  local err
  if ! err=$(osascript -e "tell application \"System Events\" to tell appearance preferences to ${action}" 2>&1); then
    print -P "%F{red}daynight: failed%f — ${err}"
    print -P "  Likely fix: System Settings → Privacy & Security → Automation → allow your terminal to control System Events."
    return 1
  fi

  local is_dark
  is_dark=$(osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode' 2>/dev/null)

  if [[ "$is_dark" == "true" ]]; then
    print -P "%F{cyan}● dark%f — ghostty theme: %F{cyan}nordish%f"
  else
    print -P "%F{yellow}○ light%f — ghostty theme: %F{yellow}beamish%f"
  fi
}



# goose — talk-to-me Goose, fix the local surfaces dev setup, then boot
# Mastra. Idempotent — safe to run anytime.
#
# Heals the most common breakage: ai-mastra-postgres bound to a stale
# compose-project from a different clone (causes Mastra startup conflicts).
# Detects which surfaces clone you're currently in (via git toplevel), so it
# Just Works whether you're in ~/Sites/homebotapp/surfaces, /surfaces-reviews,
# or any other clone.
#
# Steps (each one no-ops if already healthy):
#   1. If ai-mastra-postgres has a stale compose-project label → docker rm -f
#   2. docker compose up -d postgres
#   3. Wait for pg_isready
#   4. yalc — if any @homebotapp/* packages are linked into customer-admin,
#      rebuild + push them so the embed test exercises current source.
#      Skips entirely when nothing is linked.
#   5. Restart customer-admin (picks up the fresh yalc bundle from step 4)
#   6. Boot Mastra in the foreground via aws-vault (Ctrl-C to stop)
goose() {
  setopt local_options err_return

  local surfaces
  if surfaces=$(git rev-parse --show-toplevel 2>/dev/null) && \
     [[ -f "$surfaces/turbo.json" && -d "$surfaces/apps/ai-mastra" ]]; then
    : # already inside a surfaces clone
  else
    surfaces="$HOME/Sites/homebotapp/surfaces-reviews"
  fi

  local customer_admin="$HOME/Sites/homebotapp/customer-admin"
  local expected_project="${surfaces:t}"

  print -P "%F{cyan}🪿 goose%f → talk to me Goose, using clone: %F{yellow}$surfaces%f"

  # 1. Heal stale compose-project label on ai-mastra-postgres
  local pg_project
  pg_project=$(docker inspect ai-mastra-postgres \
    --format '{{ index .Config.Labels "com.docker.compose.project" }}' 2>/dev/null) || pg_project=""
  if [[ -n "$pg_project" && "$pg_project" != "$expected_project" ]]; then
    print -P "  %F{yellow}↻%f ai-mastra-postgres bound to '$pg_project', recreating under '$expected_project'"
    docker rm -f ai-mastra-postgres >/dev/null
  fi

  # 2. Bring up postgres (idempotent — no-op if already running)
  print -P "  %F{cyan}⚙%f docker compose up -d postgres"
  (cd "$surfaces" && docker compose up -d postgres >/dev/null)

  # 3. Wait for ready
  print -n "  ⏱ pg_isready"
  local i
  for i in {1..30}; do
    if docker exec ai-mastra-postgres pg_isready -U ai_mastra >/dev/null 2>&1; then
      print -P " %F{green}✓%f"
      break
    fi
    print -n "."
    sleep 1
  done

  # 3b. Ensure the observability database exists — a separate database on the
  # same instance (see apps/ai-mastra/README.md). A recreated container (clone
  # rebind, docker:reset) comes up without it and every chat subscribe 500s
  # with 'database "ai_mastra_observability" does not exist'. Idempotent:
  # "already exists" failures are silenced.
  if docker exec ai-mastra-postgres createdb -U ai_mastra ai_mastra_observability 2>/dev/null; then
    print -P "  %F{green}✓%f created ai_mastra_observability database"
  fi

  # 4. yalc — if any @homebotapp/* packages are linked into customer-admin,
  # rebuild and push them so the embed test exercises current source. Skips
  # entirely when nothing is linked (the lab-next-only / mastra-only loop).
  local yalc_lock="$customer_admin/yalc.lock"
  if [[ -f "$yalc_lock" ]]; then
    local linked_pkgs
    linked_pkgs=$(grep -oE '"@homebotapp/[a-z-]+"' "$yalc_lock" | tr -d '"' | sort -u)
    if [[ -n "$linked_pkgs" ]]; then
      local linked_inline=${linked_pkgs//$'\n'/ }
      print -P "  %F{cyan}⚙%f yalc-linked: %F{yellow}${linked_inline}%f"

      local filter_args=()
      local pkg
      for pkg in ${(f)linked_pkgs}; do
        filter_args+=(--filter "${pkg}...")
      done

      if (cd "$surfaces" && pnpm build "${filter_args[@]}" >/dev/null 2>&1); then
        print -P "  %F{green}✓%f built"
      else
        print -P "  %F{red}✗%f build failed — skipping yalc push"
        linked_pkgs=""  # signal: skip the per-package push loop below
      fi

      for pkg in ${(f)linked_pkgs}; do
        local short="${pkg#@homebotapp/}"
        local stage="/tmp/yalc-stage-${short}"
        rm -rf "$stage" && mkdir -p "$stage"
        if (cd "$surfaces/packages/${short}" && pnpm pack --pack-destination "$stage" >/dev/null 2>&1) && \
           (cd "$stage" && tar -xzf *.tgz >/dev/null 2>&1 && cd package && yalc push >/dev/null 2>&1); then
          print -P "  %F{green}✓%f pushed ${pkg}"
        else
          print -P "  %F{red}✗%f push failed for ${pkg}"
        fi
      done
    fi
  fi

  # 5. Restart customer-admin (picks up the fresh yalc bundle if step 4 ran)
  if docker ps --format '{{.Names}}' | grep -q '^customer-admin-customer-admin-1$'; then
    print -P "  %F{cyan}↻%f restarting customer-admin"
    docker compose -f "$customer_admin/docker-compose.yml" restart customer-admin >/dev/null
  elif [[ -d "$customer_admin" ]]; then
    print -P "  %F{cyan}⚙%f starting customer-admin"
    (cd "$customer_admin" && docker compose up -d >/dev/null)
  fi

  # 5.5. Kill stale processes on :3000 (lab-next) and :4111 (mastra gateway).
  # When switching clones or after a partial crash, an orphaned next-server
  # or gateway tsx process can survive and block the new boot. goose is the
  # canonical entry point for booting these — anything pre-existing is unwanted.
  local port stale_pid
  for port in 3000 4111; do
    stale_pid=$(lsof -ti :$port -sTCP:LISTEN 2>/dev/null | head -1)
    if [[ -n "$stale_pid" ]]; then
      print -P "  %F{yellow}↻%f killing stale process on :$port (pid $stale_pid)"
      # `|| true` — kill fails when the pid is already gone, which is the
      # desired outcome; without it err_return silently aborts the function
      kill "$stale_pid" 2>/dev/null || true
      sleep 1
      # If still alive after SIGTERM, force it
      kill -9 "$stale_pid" 2>/dev/null || true
    fi
  done

  # 5.6. node_modules freshness — probe a known dep from ai-mastra's package.json.
  # When package.json gains a new dep on main and you switch to a stale clone
  # branched before that, tsx will hang or crash with ERR_MODULE_NOT_FOUND.
  # Probe is a cheap symlink check; pnpm install only runs if it's missing.
  if [[ ! -d "$surfaces/apps/ai-mastra/node_modules/@graphql-hive/gateway-runtime" ]]; then
    print -P "  %F{yellow}⚙%f node_modules stale — running pnpm install"
    (cd "$surfaces" && pnpm install) || {
      print -P "  %F{red}✗%f pnpm install failed — Mastra boot will likely crash"
    }
  fi

  # 6. Boot Mastra in the foreground (Ctrl-C to stop, prompt returns).
  # Wrapped in `aws-vault exec dev-sso` so the Bedrock-backed memory tier can
  # SigV4-sign InvokeModel calls — fromNodeProviderChain() resolves only from
  # the AWS_* env vars aws-vault injects (see docs/bedrock-inference.md).
  # Subshell so the user's cwd is preserved if they ran goose from a
  # subdirectory of the clone.
  print -P "\n%F{green}✓ Setup ready.%f %F{cyan}Booting Mastra%f — Ctrl-C to stop"
  print -P "  Visit %F{cyan}https://customer-admin.homebot.test%f or %F{cyan}http://localhost:3000%f (lab-next)\n"
  # aws-vault refuses to nest (errors if AWS_VAULT is already set). A dev-sso
  # subshell may reuse its creds — but only after verifying they still WORK
  # (SSO sessions expire; a gateway booted with dead/missing creds fails every
  # Bedrock call with "Could not load credentials from any providers"). Any
  # other/stale vault state gets scrubbed before re-execing so Mastra never
  # boots with the wrong account's creds.
  if [[ "$AWS_VAULT" == "dev-sso" ]] && aws sts get-caller-identity >/dev/null 2>&1; then
    (cd "$surfaces" && pnpm mastra:dev)
  elif [[ -n "$AWS_VAULT" ]]; then
    print -P "  %F{yellow}↻%f aws-vault subshell '%F{yellow}$AWS_VAULT%f' unusable (wrong profile or expired) — re-execing as dev-sso"
    (cd "$surfaces" && env -u AWS_VAULT -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY \
      -u AWS_SESSION_TOKEN -u AWS_CREDENTIAL_EXPIRATION -u AWS_SESSION_EXPIRATION \
      aws-vault exec dev-sso -- pnpm mastra:dev)
  else
    (cd "$surfaces" && aws-vault exec dev-sso -- pnpm mastra:dev)
  fi
}

# Push local surfaces package changes into the running customer-admin
# container. The mid-day companion to goose: goose owns the morning boot
# (and re-running it would kill your dev servers); sync-ca just relays a
# package edit across the yalc bridge. There is no HMR across this boundary —
# the container copies packages into its node_modules volume at npm-install
# time, so every push needs the container restart this performs.
# Usage: sync-ca [pkg ...]   e.g. `sync-ca ui` — defaults to all linked pkgs.
sync-ca() {
  setopt local_options err_return
  local surfaces
  if surfaces=$(git rev-parse --show-toplevel 2>/dev/null) \
      && [[ -f "$surfaces/turbo.json" && -d "$surfaces/apps/ai-mastra" ]]; then
    :
  else
    surfaces="$HOME/Sites/homebotapp/surfaces"
  fi
  local customer_admin="$HOME/Sites/homebotapp/customer-admin"

  local -a pkgs
  if (( $# > 0 )); then
    pkgs=("$@")
  else
    pkgs=(${(f)"$(grep -oE '"@homebotapp/[a-z-]+"' "$customer_admin/yalc.lock" \
      | tr -d '"' | sed 's|@homebotapp/||' | sort -u)"})
  fi
  (( ${#pkgs} > 0 )) || { print -P "%F{red}✗%f nothing yalc-linked"; return 1 }

  local -a filter_args
  local pkg
  for pkg in "${pkgs[@]}"; do
    filter_args+=(--filter "@homebotapp/${pkg}...")
  done
  print -P "  %F{cyan}⚙%f building: %F{yellow}${pkgs[*]}%f"
  (cd "$surfaces" && pnpm build "${filter_args[@]}" >/dev/null 2>&1) \
    || { print -P "%F{red}✗%f build failed"; return 1 }

  for pkg in "${pkgs[@]}"; do
    local stage="/tmp/yalc-stage-${pkg}"
    rm -rf "$stage" && mkdir -p "$stage"
    if (cd "$surfaces/packages/${pkg}" && pnpm pack --pack-destination "$stage" >/dev/null 2>&1) \
        && (cd "$stage" && tar -xzf *.tgz >/dev/null 2>&1 && cd package && yalc push >/dev/null 2>&1); then
      print -P "  %F{green}✓%f pushed @homebotapp/${pkg}"
    else
      print -P "  %F{red}✗%f push failed for @homebotapp/${pkg}"
      return 1
    fi
  done

  print -P "  %F{cyan}↻%f restarting customer-admin (npm install re-copies packages — ~60s)"
  docker compose -f "$customer_admin/docker-compose.yml" restart customer-admin >/dev/null
  print -P "  %F{green}✓%f done — hard-reload the browser (Cmd+Shift+R) once it's back"
}

# Window layout utility
[[ -f "$HOME/dotfiles/layout.zsh" ]] && source "$HOME/dotfiles/layout.zsh"

# To track secrets like GH PAT
[ -f ~/.secrets ] && source ~/.secrets

# Pritunl CLI (added by hb:vpn-setup)
alias pritunl="/Applications/Pritunl.app/Contents/Resources/pritunl-client"
