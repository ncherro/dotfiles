# profile zsh
# zmodload zsh/zprof

export HISTFILE=~/.zhistory

# Antigen config
source ~/antigen.zsh

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


export EDITOR='vim'
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export TZ=America/Chicago

# git
export GIT_MERGE_AUTOEDIT=no
alias g-='gco -'
alias gpf='git pf'
alias gpc='git push --set-upstream origin "$(git rev-parse --abbrev-ref HEAD 2> /dev/null)"'
alias gd='gwd'
alias gsq='git reset --soft $(git merge-base master HEAD)' # squash all commits in branch
alias gdm='git branch --merged | grep -v "^\*\\|master" | xargs -n 1 git branch -d' # delete all merged branches

deletemerged() {
  git branch --merged | grep -v "\*" | xargs -n 1 git branch -d
}

# Postgres
export PGDATA=/usr/local/var/postgres
alias pg-start='pg_ctl -D /usr/local/var/postgres -l /usr/local/var/postgres/server.log start'
alias pg-stop='pg_ctl -D /usr/local/var/postgres stop -s -m fast'
alias pg-status='pg_ctl -D /usr/local/var/postgres status'

# tmux
alias tls="tmux ls"

tatt() {
  tmux at -t $1
}

tat() {
  # get the current directory name
  dirname=${PWD##*/}
  # try to create a new session (hide errors)
  tmux new -s $dirname # 2>&1 /dev/null
  # attach to the session
  tatt $dirname
}

tks() {
  tmux kill-server
}

# cd to the git root, then cd one level up then back in to help RVM
cd.() {
  cd $(git rev-parse --show-toplevel) && cd ../ && cd -;
}

# nginx
alias nginx-start="sudo nginx"
alias nginx-stop="sudo /usr/local/bin/nginx -s stop"
alias nginx-reload="sudo /usr/local/bin/nginx -s reload"
alias sites-enabled="cd /usr/local/etc/nginx/sites-enabled"
nginx-restart() {
  nginx-stop;
  nginx-start;
}

# other aliases
alias l="ls -alh"

alias stamp="date +%F-%H%M%S"

# disable autocorrect
alias cap="nocorrect cap"

alias v="vim"

ulimit -n 10000

export CLICOLOR=1

# nodejs modules
export NODE_PATH=/usr/local/lib/node_modules


# Set up fzf key bindings and fuzzy completion
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

# https://github.com/sindresorhus/pure
autoload -Uz promptinit; promptinit
prompt pure

alias k8s-contexts="grep '^- name: ' ~/.kube/config | awk '{print $3}'"
alias k8s-prod-clusters="gcloud container clusters list --project=gke-xpn-1 --filter=\"resourceLabels[env]=production\" --format=\"value(name)\""
alias k8s-sync="kubectl site sync-creds"

alias gitpersonal="git config user.email \"ncherro@gmail.com\""

export WORKSPACE="$HOME/workspace"

alias ws="cd $WORKSPACE";

export LD_LIBRARY_PATH=/home/ebenezer/workspace/vid.stab:$LD_LIBRARY_PATH
