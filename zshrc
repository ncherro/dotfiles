# profile zsh
# zmodload zsh/zprof

export HISTFILE=~/.zhistory

# Antigen config
source /usr/local/share/antigen/antigen.zsh

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

# apply ^
antigen apply

# https://github.com/sindresorhus/pure
prompt pure

# Base16 Shell
BASE16_SHELL="$HOME/.config/base16-shell/"
[ -n "$PS1" ] && \
    [ -s "$BASE16_SHELL/profile_helper.sh" ] && \
        eval "$("$BASE16_SHELL/profile_helper.sh")"

# /usr/local/ first, for homebrew
PATH=/usr/local/bin:/usr/local/sbin:$PATH
export PATH=/usr/local/share/npm/bin:$PATH
export PATH=$PATH:~/Development/android-sdk-macosx/platform-tools:~/Development/android-sdk-macosx/tools
export PATH=$PATH:~/Library/Python/2.7/bin
export PATH=$PATH:~/Projects/namely/grpc/bins/opt

export EDITOR='nvim'
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export TZ=America/New_York
export SHELL=/usr/local/bin/zsh


# git
export GIT_MERGE_AUTOEDIT=no
alias g-='gco -'
alias gpf='git pf'
alias gpc='git push --set-upstream origin "$(git rev-parse --abbrev-ref HEAD 2> /dev/null)"'
alias gd='gwd'

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

# ssh agent
if [ -f ~/.agent.env ] ; then
    . ~/.agent.env > /dev/null
if ! kill -0 $SSH_AGENT_PID > /dev/null 2>&1; then
    echo "Stale agent file found. Spawning new agent… "
    eval `ssh-agent | tee ~/.agent.env`
    ssh-add
fi 
else
    echo "Starting ssh-agent"
    eval `ssh-agent | tee ~/.agent.env`
    ssh-add
fi

alias v="nvim"

ulimit -n 10000

export CLICOLOR=1

# nodejs modules
export NODE_PATH=/usr/local/lib/node_modules

## Go
export GOPATH=$HOME/go
export GOROOT=/usr/local/opt/go/libexec
export GOBIN=$GOPATH/bin
export PATH=$PATH:$GOPATH/bin
export PATH=$PATH:$GOROOT/bin
export GIT_TERMINAL_PROMPT=1 # allow go get for github repos
export GO111MODULE=on


#export FZF_DEFAULT_COMMAND='
  #(git ls-tree -r --name-only HEAD ||
       #find . -path "*/\.*" -prune -o -type f -print -o -type l -print |
        #sed s/^..//) 2> /dev/null'

export FZF_DEFAULT_COMMAND='rg --files --no-ignore --hidden --follow --glob "!.git/*"'

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

#alias elasticsearch="elasticsearch --config=/usr/local/opt/elasticsearch17/config/elasticsearch.yml"
export PATH="$HOME/.exenv/bin:$PATH"
#eval "$(exenv init -)"

alias gti="git"

function exportFile() {
  set -o allexport; source $1; set +o allexport;
}

alias dco=docker-compose
alias dc=docker-compose
#alias dmc=docker-machine
#alias edmc='eval $(docker-machine env default)'

# k8s
export KUBECONFIG=/Users/nickherro/.kube/config
export TILLER_NAMESPACE=default

alias gsha="git rev-parse --short HEAD"
alias h="history"

# profile zsh
# zprof

alias an="cd ~/Projects/anchor"

alias ngrok="~/ngrok"

export NVM_DIR="$HOME/.nvm"
[ -s "/usr/local/opt/nvm/nvm.sh" ] && . "/usr/local/opt/nvm/nvm.sh"  # This loads nvm
[ -s "/usr/local/opt/nvm/etc/bash_completion" ] && . "/usr/local/opt/nvm/etc/bash_completion"  # This loads nvm bash_completion
