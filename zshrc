# profile zsh
# zmodload zsh/zprof

export HISTFILE=~/.zhistory

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

# --- Editor and Locale ---
export EDITOR='vim'
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export TZ=America/Chicago
export SHELL=/opt/homebrew/bin/zsh

# --- Git Aliases and Functions ---
export GIT_MERGE_AUTOEDIT=no
alias g-='gco -'
alias gpf='git pf'
alias gpc='git push --set-upstream origin "$(git rev-parse --abbrev-ref HEAD 2> /dev/null)"'
alias gd='gwd'
alias gsq='git reset --soft $(git merge-base master HEAD)'
alias gdm='git branch --merged | grep -v "^\*\\|master" | xargs -n 1 git branch -d'
alias gs='git switch'
alias gfr='git pull --rebase'

deletemerged() {
  git branch --merged | grep -v "\*" | xargs -n 1 git branch -d
}

# --- Postgres ---
export PGDATA=/usr/local/var/postgres
alias pg-start='pg_ctl -D /usr/local/var/postgres -l /usr/local/var/postgres/server.log start'
alias pg-stop='pg_ctl -D /usr/local/var/postgres stop -s -m fast'
alias pg-status='pg_ctl -D /usr/local/var/postgres status'

# --- Tmux ---
alias tls="tmux ls"

tatt() {
  tmux at -t $1;
}

tat() {
  dirname=${PWD##*/}
  tmux ls | grep "${dirname}" && { tmux at -t $dirname; return 0; }
  mux ls | grep "${dirname}" && { mux start $dirname; return 0; }
  tmux new -s $dirname
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
alias mcv='mvn clean verify'
alias mci='mvn clean install'
alias mcg='mvn clean generate-sources'
alias mvn-clear-cache="rm -Rf ~/.m2/repository"

# --- SDKMAN ---
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

if type brew &>/dev/null; then
    FPATH=$(brew --prefix)/share/zsh-completions:$FPATH
    autoload -Uz compinit
    compinit
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

alias gitpersonal="git config user.email \"ncherro@gmail.com\""
alias gitwork="git config user.email \"nicholash@spotify.com\""

export BGP_SERVICE_ID="nicholash-golden-path-tutorial"
export BGP_SERVICE_ID_WITHOUT_DASHES="nicholashgoldenpathtutorial"
export WORKSPACE="$HOME/workspace"

# --- PATH Setup (consolidated) ---
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/local/sbin:/usr/local/share/npm/bin:/opt/homebrew/opt/mysql-client/bin:/Users/nicholash/workspace/dev/scripts:/opt/spotify-devex/bin:/Users/nicholash/.local/bin:/opt/homebrew/opt/mysql-client@8.4/bin:/Users/nicholash/.pyenv/shims:$PATH"

alias ws="cd $WORKSPACE"

function ecr-login() {
  aws ecr get-login-password | docker login --username AWS --password-stdin 523887678637.dkr.ecr.us-east-1.amazonaws.com
}

alias mux="tmuxinator"

alias ghopen="git config --get remote.origin.url | sed 's/:/\//' | sed 's/git@/https:\/\//' | sed 's/.git//' | xargs open"

source ~/.spotify.config

export PATH="/Users/nicholash/.pyenv/shims:${PATH}"
export PYENV_SHELL=zsh
source '/opt/homebrew/Cellar/pyenv/2.5.3/completions/pyenv.zsh'
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
export PATH=/opt/spotify-devex/bin:$PATH
