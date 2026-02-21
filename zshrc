# profile zsh
# zmodload zsh/zprof

export HISTFILE=~/.zhistory

# Cache brew prefix to avoid repeated subprocess calls (~500ms savings)
export HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"

# Antidote plugin manager (faster than antigen)
source $HOMEBREW_PREFIX/opt/antidote/share/antidote/antidote.zsh
antidote load ${ZDOTDIR:-$HOME}/.zsh_plugins.txt

# --- Editor and Locale ---
export EDITOR='vim'
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export TZ=America/Chicago
export SHELL=/opt/homebrew/bin/zsh

# --- Git Aliases and Functions ---
export GIT_MERGE_AUTOEDIT=no

# Git aliases
alias gp='git push'
alias gpf='git pf'
alias gpc='git push --set-upstream origin "$(git rev-parse --abbrev-ref HEAD 2> /dev/null)"'
alias gd='git add -N . && git diff && git reset'
alias gsq='git reset --soft $(git merge-base master HEAD)'
alias gdm='git branch --merged | grep -v "^\*\\|master" | xargs -n 1 git branch -d'
alias gs='git switch'
alias gfr='git pull --rebase'
alias gfa='git fetch --all'
alias gfl='spt git:fetch-local && if [ "$(git branch --show-current)" = "master" ]; then git merge --ff-only origin/master; else git fetch . origin/master:master; fi'
alias glo='git log'

# gco: git checkout with auto-prefix for new branches
gco() {
  if [[ "$1" == "-b" && -n "$2" && "$2" != $USER/* ]]; then
    git checkout -b "$USER/$2" "${@:3}"
  else
    git checkout "$@"
  fi
}
alias g-='gco -'

# Branch completion for git aliases (workaround for git 2.52+ bug)
_git_branch_complete() {
  compadd ${(f)"$(git branch -a 2>/dev/null | sed 's/^[* ]*//' | sed 's|remotes/origin/||' | sort -u)"}
}

deletemerged() {
  git branch --merged | grep -v "\*" | xargs -n 1 git branch -d
}

# --- Postgres ---
export PGDATA=/usr/local/var/postgres
alias pg-start='pg_ctl -D /usr/local/var/postgres -l /usr/local/var/postgres/server.log start'
alias pg-stop='pg_ctl -D /usr/local/var/postgres stop -s -m fast'
alias pg-status='pg_ctl -D /usr/local/var/postgres status'

# --- Tmux ---
# Show sessions with indicator for running processes
tls() {
  tmux ls -F '#{session_name}' 2>/dev/null | while read -r session; do
    procs=$(tmux list-windows -t "$session" -F '#{pane_current_command}' | grep -v '^zsh$' | tr '\n' ' ')
    if [[ -n "$procs" ]]; then
      echo "⚡ $session: $procs"
    else
      echo "  $session"
    fi
  done
}

tatt() {
  tmux at -t $1;
}

tat() {
  dirname=${PWD##*/}
  # Check for an exact match in tmux session names
  if tmux ls 2>/dev/null | grep -q "^${dirname}:"; then
    tmux at -t "$dirname"
    return 0
  fi
  # If using mux (tmuxinator), check for an exact match
  if mux ls 2>/dev/null | grep -q "^${dirname}"; then
    mux start "$dirname"
    return 0
  fi
  # Otherwise, create a new tmux session
  tmux new -s "$dirname"
}

tks() {
  tmux kill-server
}

# --- Miscellaneous Aliases and Functions ---
alias l="ls -alh"
alias stamp="date +%F-%H%M%S"
alias cap="nocorrect cap"
alias v="vim"
ulimit -n 10000
export CLICOLOR=1
export LSCOLORS=ExFxBxDxCxegedabagacad
export NODE_PATH=/usr/local/lib/node_modules

# --- FZF ---
source <(fzf --zsh 2>/dev/null)
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'

alias gti="git"

function exportFile() {
  set -o allexport; source $1; set +o allexport;
}

alias dco=docker-compose
alias dc=docker-compose

alias gsha="git rev-parse --short HEAD"
alias h="history"

setopt inc_append_history
setopt share_history

# profile zsh
# zprof

alias ngrok="~/ngrok"

# focus
alias focus="sudo bash ~/block-sites.sh"
alias unfocus="sudo bash ~/unblock-sites.sh"

# --- NVM (lazy loaded for ~1.5s faster startup) ---
export NVM_DIR="$HOME/.nvm"

# Lazy load nvm - only initialize when first used
_load_nvm() {
  unset -f nvm node npm npx yarn pnpm 2>/dev/null
  [ -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ] && \. "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
  [ -s "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm" ] && \. "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm"
}

nvm() { _load_nvm && nvm "$@"; }
node() { _load_nvm && node "$@"; }
npm() { _load_nvm && npm "$@"; }
npx() { _load_nvm && npx "$@"; }
yarn() { _load_nvm && yarn "$@"; }
pnpm() { _load_nvm && pnpm "$@"; }

autoload -U add-zsh-hook

# Auto-switch node version when entering a directory with .nvmrc
_auto_nvm_use() {
  if [[ -f .nvmrc ]]; then
    _load_nvm
    nvm use
  fi
}
add-zsh-hook chpwd _auto_nvm_use
# Run once for the initial directory
_auto_nvm_use

# --- Java & Maven ---
export JAVA_HOME="$(/usr/libexec/java_home -v 21)"
alias mcl='mvn clean'
alias mve='mvn verify'
alias mcv='mvn clean verify'
alias mcut='mvn clean verify -DskipITs' # only clean, verify, and run unit tests
alias mcit='mvn clean verify -Dsurefire.skip=true' # only clean, verify, and run integration tests
alias mci='mvn clean install'
alias mcg='mvn clean generate-sources'
alias mcp='mvn clean package -P uberJar' # do this before `java-run`
alias mvn-clear-cache="rm -Rf ~/.m2/repository"
alias openapi-generator-cli='java -jar ~/openapi-generator-cli.jar'

# --- SDKMAN ---
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# Use cached HOMEBREW_PREFIX instead of $(brew --prefix) calls
FPATH=$HOMEBREW_PREFIX/share/zsh-completions:$FPATH
autoload -Uz compinit
# Only regenerate compinit dump once per day for faster startup
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C  # Use cached completions
fi
compdef _git_branch_complete gco gs
source "$HOMEBREW_PREFIX/opt/zsh-git-prompt/zshrc.sh"

autoload -Uz promptinit; promptinit
prompt pure

# Google Cloud SDK (deduplicated - only load once)
source "$HOMEBREW_PREFIX/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc"
source "$HOMEBREW_PREFIX/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc"

# --- Kubernetes ---
alias k8s="kubectl"
alias k8s-contexts="grep '^- name: ' ~/.kube/config | awk '{print $3}'"
alias k8s-prod-clusters="gcloud container clusters list --project=gke-xpn-1 --filter=\"resourceLabels[env]=production\" --format=\"value(name)\""
alias k8s-sync="kubectl site sync-creds"
alias k8s-bash='k8s exec -it $(k8s get po | grep Running | awk "{print $1}" | tail -n 1) -- bash'

alias gitpersonal="git config user.email \"ncherro@gmail.com\""
alias gitwork="git config user.email \"nicholash@spotify.com\""

export BGP_SERVICE_ID="nicholash-golden-path-tutorial"
export BGP_SERVICE_ID_WITHOUT_DASHES="nicholashgoldenpathtutorial"
export WORKSPACE="$HOME/workspace"

# --- PATH Setup (consolidated) ---
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/local/sbin:/usr/local/share/npm/bin:/opt/homebrew/opt/mysql-client/bin:/Users/nicholash/workspace/dev/scripts:/opt/spotify-devex/bin:/Users/nicholash/.local/bin:/opt/homebrew/opt/mysql-client@8.4/bin:/Users/nicholash/.pyenv/shims:$PATH"
export PATH="/Applications/IntelliJ IDEA.app/Contents/MacOS:$PATH"

alias ws="cd $WORKSPACE"

function ecr-login() {
  aws ecr get-login-password | docker login --username AWS --password-stdin 523887678637.dkr.ecr.us-east-1.amazonaws.com
}

alias mux="tmuxinator"

# open in github / GHE
alias ghopen="git config --get remote.origin.url | sed 's/:/\//' | sed 's/git@/https:\/\//' | sed 's/\.git//' | xargs open"

# find and open the PR for current branch
ghpr() {
  gh pr view --web 2>/dev/null || echo "No PR found for branch: $(git rev-parse --abbrev-ref HEAD)"
}

# open Jira ticket from branch name (e.g., nicholash/ABC-1234-foo-bar -> http://jira.com/browse/ABC-1234)
jira() {
  local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  local key=$(echo "$branch" | grep -oE '[A-Z]{2,}-[0-9]+' | head -1)
  if [[ -n "$key" ]]; then
    open "https://spotify.atlassian.net/browse/$key"
  else
    echo "No Jira key found in branch: $branch"
  fi
}

# cd to git project root
cd.() {
  cd "$(git rev-parse --show-toplevel)"
}

alias c=claude

alias bazel=bazelisk

# add our scripts dir to the PATH
export PATH="$HOME/scripts:${PATH}"

# Spotify stuff
export PATH="$HOME/.pyenv/shims:${PATH}"
export PYENV_SHELL=zsh
if command -v pyenv >/dev/null; then
  completions_dir="$(pyenv root)/completions/pyenv.zsh"
  [ -f "$completions_dir" ] && source "$completions_dir"
fi
command pyenv rehash 2>/dev/null
pyenv() {
  local command=${1:-}
  [ "$#" -gt 0 ] && shift
  case "$command" in
  rehash|shell)
    eval "$(pyenv "sh-$command" "$@")"
    ;;
  *)
    command pyenv "$command" "$@"
    ;;
  esac
}

source ~/.spotify.config
source ~/.env

# Add RVM to PATH for scripting. Make sure this is the last PATH variable change.
export PATH="$PATH:$HOME/.rvm/bin"
export PATH=/opt/spotify-devex/bin:$PATH
alias terminal="open -a Kitty"
