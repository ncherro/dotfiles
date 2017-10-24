# using_gcc for 64btt compiling on lion (solves compatability issues)
function using_gcc() {
  env CC="/usr/bin/gcc-4.2" ARCHFLAGS="-arch x86_64" ARCHS="x86_64" $*
}

# Path to your oh-my-zsh configuration.
export ZSH=$HOME/.oh-my-zsh

# Set to the name theme to load.
# Look in ~/.oh-my-zsh/themes/
export ZSH_THEME="geoffgarside"

# plugins can be found in ~/.oh-my-zsh/plugins/*
plugins=(rails git github ruby)

source $ZSH/oh-my-zsh.sh

# custom prompt
PROMPT='[%*] %{$fg[magenta]%}%n%{$reset_color%}:%{$fg[green]%}%c%{$reset_color%}$(git_prompt_info) %(!.#.$) '

# /usr/local/ first, for homebrew
PATH=/usr/local/bin:/usr/local/sbin:$PATH
export PATH=/usr/local/share/npm/bin:$PATH
export PATH=$PATH:~/Development/android-sdk-macosx/platform-tools:~/Development/android-sdk-macosx/tools

export EDITOR='vim'
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export TZ=America/New_York
export SHELL=/usr/local/bin/zsh


# git
export GIT_MERGE_AUTOEDIT=no
alias g-='gco -'
gpp() {
  eval "git push --set-upstream origin $(git name-rev --name-only HEAD)"
}

# website stuff
alias profiles='open ~/profiles.tmproj'
alias ts='date +"%F_%T"' # prints a timestamp - e.g. echo "asdf`ts`"
alias projects='cd ~/Projects'
alias iphone='cd ~/Projects/iPhone'

# Postgres
export PGDATA=/usr/local/var/postgres
alias pg-start='pg_ctl -D /usr/local/var/postgres -l /usr/local/var/postgres/server.log start'
alias pg-stop='pg_ctl -D /usr/local/var/postgres stop -s -m fast'
alias pg-status='pg_ctl -D /usr/local/var/postgres status'

# Git
alias gfa='git fetch --all'
alias gfu='git fetch upstream'

# tmux list sessions
alias tls="tmux ls"

# tmux attach
tatt() {
  tmux at -t $1
}

# tmux attach
tat() {
  # get the current directory name
  dirname=${PWD##*/}
  # try to create a new session (hide errors)
  tmux new -s $dirname # 2>&1 /dev/null
  # attach to the session
  tatt $dirname
}

# tmux kill server
tks() {
  tmux kill-server
}

# mongodb
alias mongodb.start="mongod --fork --logpath /var/log/mongodb.log --logappend"

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

# memcached
alias memcached-start="/usr/local/opt/memcached/bin/memcached -d"

alias redis-start="redis-server /usr/local/etc/redis.conf"
alias flushredis="echo 'FLUSHALL' | redis-cli"

# PHP-FPM
alias php54-start="sudo launchctl load -w /Library/LaunchAgents/homebrew-php.josegonzalez.php54.plist"
#alias php53-start="sudo launchctl load -w /Library/LaunchAgents/homebrew-php.josegonzalez.php53.plist"
php-stop() {
  if [ -f "/usr/local/var/run/php-fpm.pid" ]; then
    echo "Stopping PHP-FPM..."
    pid=$(cat /usr/local/var/run/php-fpm.pid)
    kill -TERM $pid
  else
    echo "PHP-FPM does not appear to be running"
  fi
}
php-graceful-stop() {
  if [ -f "/usr/local/var/run/php-fpm.pid" ]; then
    echo "Gracefully stopping PHP-FPM..."
    pid=$(cat /usr/local/var/run/php-fpm.pid)
    kill -QUIT $pid
  else
    echo "PHP-FPM does not appear to be running"
  fi
}
php-reload() {
  if [ -f "/usr/local/var/run/php-fpm.pid" ]; then
    echo "Reloading PHP-FPM..."
    pid=$(cat /usr/local/var/run/php-fpm.pid)
    kill -USR2 $pid
  else
    echo "PHP-FPM does not appear to be running"
  fi
}

# other aliases
alias l="ls -alh"

alias stamp="date +%F-%H%M%S"

# disable autocorrect
alias cap="nocorrect cap"

killport() {
  if [ -n "${1}" ]; then
    port=$1
  else
    # default (Rails-centric)
    port="3000"
  fi
  pid=`lsof -wni tcp:$port | grep 'ruby' | awk 'NR==1 { print $2 }'`
  if [ -n "${pid}" ]; then
    kill -9 $pid
    echo "Killed process $pid"
  else
    echo "No processes were found listening on tcp:$port"
  fi
}

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

alias v="vim"
alias z="zeus"
alias zc="zeus c"
alias zs="zeus start"
alias zr="zeus s"
alias zmig="zeus rake db:migrate"
alias zt="unset AWS_SECRET_ACCESS_KEY && unset AWS_ACCESS_KEY_ID && zeus rspec spec"

alias venv='. ./venv/bin/activate'

ulimit -n 10000

#export PYTHONPATH=$(brew --prefix)/lib/python2.7/site-packages:$PYTHONPATH

alias npmgrunt="npm install && grunt server"

deletemerged() {
  git branch --merged | grep -v "\*" | xargs -n 1 git branch -d
}

source /usr/local/share/zsh/site-functions/_aws

export CLICOLOR=1

# nodejs modules
export NODE_PATH=/usr/local/lib/node_modules

# set our env vars
if [ -f ~/.env ]; then
  source ~/.env
else
  print "~/.env file not found"
fi
### Added by the Heroku Toolbelt
export PATH="/usr/local/heroku/bin:$PATH"

## Go
# temporary 1.7 override
# https://github.com/golang/go/issues/18172
export GOPATH=$HOME/golang
export GOROOT=/usr/local/opt/go/libexec
export PATH=$PATH:$GOPATH/bin
export PATH=$PATH:$GOROOT/bin

export FZF_DEFAULT_COMMAND='
  (git ls-tree -r --name-only HEAD ||
       find . -path "*/\.*" -prune -o -type f -print -o -type l -print |
        sed s/^..//) 2> /dev/null'

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

#alias elasticsearch="elasticsearch --config=/usr/local/opt/elasticsearch17/config/elasticsearch.yml"
export PATH="$HOME/.exenv/bin:$PATH"
#eval "$(exenv init -)"

alias gti="git"


## Android development
export ANDROID_HOME=$HOME/Library/Android/sdk
PATH="$HOME/Library/Android/sdk/tools:$HOME/Library/Android/sdk/platform-tools:${PATH}"
export PATH

function exportFile() {
  set -o allexport; source $1; set +o allexport;
}

# rbenv
eval "$(rbenv init -)"

# docker
docker_running=$(docker-machine ls | grep default)
if [[ "$docker_running" == *"Stopped"* ]]
then
  docker-machine start default
  eval "$(docker-machine env default)"
  env | grep "DOCKER_HOST"
elif [[ "$docker_running" == *"Running"* ]]
then
  eval "$(docker-machine env default)"
fi

alias dco=docker-compose
alias dmc=docker-machine

#source ~/.autoenv/activate.sh

source ~/.namely.config

# k8s
export KUBECONFIG=/Users/nickherro/.kube/config
export TILLER_NAMESPACE=default

alias gsha="git rev-parse --short HEAD"
alias h="history"

export NVM_DIR="$HOME/.nvm"
  . "/usr/local/opt/nvm/nvm.sh"

# realtime
export NATS_HOST=172.16.13.174
export NATS_PORT=4221
export NATS_WS_HOST=${NATS_HOST}
export NATS_WS_PORT=4223
