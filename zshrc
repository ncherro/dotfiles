# profile zsh
# zmodload zsh/zprof

export HISTFILE=~/.zhistory

if [[ -z $ANTIGEN_LOADED ]]; then
  export ANTIGEN_LOADED=1
  # Antigen config
  source /opt/homebrew/share/antigen/antigen.zsh

  # use the prezto framework
  antigen use prezto

  # load prezto modules
  antigen bundle history
  antigen bundle helper
  antigen bundle editor
  antigen bundle git
  antigen bundle tmux
  antigen bundle prompt

  # other bundles
  antigen bundle zsh-users/zsh-syntax-highlighting
  # antigen bundle bobsoppe/zsh-ssh-agent - just run `ssh-add -k` after startup to add keys

  # apply ^
  antigen apply
fi

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
alias gd='gwd'
alias gsq='git reset --soft $(git merge-base master HEAD)'
alias gdm='git branch --merged | grep -v "^\*\\|master" | xargs -n 1 git branch -d'
alias gs='git switch'
alias gfr='git pull --rebase'
alias gfa='git fetch --all'
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
source <(fzf --zsh)
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

# --- NVM ---
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion

autoload -U add-zsh-hook

load-nvmrc() {
local nvmrc_path
nvmrc_path="$(nvm_find_nvmrc)"
if [ -n "$nvmrc_path" ]; then
	local nvmrc_node_version
	nvmrc_node_version=$(nvm version "$(cat "${nvmrc_path}")")

	if [ "$nvmrc_node_version" = "N/A" ]; then
		nvm install
	elif [ "$nvmrc_node_version" != "$(nvm version)" ]; then
		nvm use
	fi
elif [ -n "$(PWD=$OLDPWD nvm_find_nvmrc)" ] && [ "$(nvm version)" != "$(nvm version default)" ]; then
	echo "Reverting to nvm default version"
	nvm use default
fi
}

add-zsh-hook chpwd load-nvmrc
load-nvmrc

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

if type brew &>/dev/null; then
    FPATH=$(brew --prefix)/share/zsh-completions:$FPATH
    autoload -Uz compinit
    compinit
    compdef _git_branch_complete gco gs
    source "$(brew --prefix)/opt/zsh-git-prompt/zshrc.sh"
    PROMPT='%B%m%~%b$(git_super_status) %# '
fi

autoload -Uz promptinit; promptinit
prompt pure

source "$(brew --prefix)/share/google-cloud-sdk/path.zsh.inc"
source "$(brew --prefix)/share/google-cloud-sdk/completion.zsh.inc"
source "$(brew --prefix)/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc"
source "$(brew --prefix)/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc"

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
