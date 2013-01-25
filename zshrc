# using_gcc for 64btt compiling on lion (solves compatability issues)
function using_gcc() {
  env CC="/usr/bin/gcc-4.2" ARCHFLAGS="-arch x86_64" ARCHS="x86_64" $*
}

# Path to your oh-my-zsh configuration.
export ZSH=$HOME/.oh-my-zsh

# Set to the name theme to load.
# Look in ~/.oh-my-zsh/themes/
export ZSH_THEME="geoffgarside"

# do not auto update .zsh
DISABLE_AUTO_UPDATE="true"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Example format: plugins=(rails git textmate ruby lighthouse)
plugins=(rails git github ruby rails3)

source $ZSH/oh-my-zsh.sh


# Customize to your needs...
PROMPT='[%*] %{$fg[magenta]%}%n%{$reset_color%}:%{$fg[green]%}%c%{$reset_color%}$(git_prompt_info) %(!.#.$) '

# /usr/local/ first, for homebrew
# homebrew-installed python site packages
PATH=/usr/local/bin:/usr/local/sbin:/Users/nherro/.cabal/bin:$PATH
PATH=/usr/local/share/python:$PATH
export PATH=$PATH
export EDITOR='vim'
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export TZ=America/New_York
export SHELL=/usr/local/bin/zsh

export SQLPATH="/usr/local/oracle/instantclient_10_2"
export TNS_ADMIN="/usr/local/oracle/network/admin"
export NLS_LANG="AMERICAN_AMERICA.UTF8"
#export PYTHONPATH=".:/usr/local/bin/python"
#export WORKON_HOME=~/.virtualenv
#source /usr/local/bin/virtualenvwrapper.sh


# website stuff
alias www='cd ~/Projects/www'
alias flash='cd ~/Projects/Flash'
alias profiles='open ~/profiles.tmproj'
alias ts='date +"%F_%T"' # prints a timestamp - e.g. echo "asdf`ts`"
alias projects='cd ~/Projects'
alias iphone='cd ~/Projects/iPhone'
alias drushdump='drush sql-dump --result-file --gzip --structure-tables-key=common'
alias flushcache='dscacheutil -flushcache'

alias edc='www && cd nycedc/public'

# mvim stuff
alias medc='mvim ~/Projects/www/nycedc-mvim'
alias mdink='mvim ~/Projects/www/daily-ink-mvim'

# Drupal stuff
alias cc='drush cc all'
alias fd='drush fd'

# Postgres
alias pg-start='pg_ctl -D /usr/local/var/postgres -l /usr/local/var/postgres/server.log start'
alias pg-stop='pg_ctl -D /usr/local/var/postgres stop -s -m fast'
alias pg-start-namely='pg_ctl -D /usr/local/var/namely -l logfile start'
alias pg-stop-namely='pg_ctl -D /usr/local/var/namely stop -s -m fast'

# RVM
[[ -s "$HOME/.rvm/scripts/rvm" ]] && . "$HOME/.rvm/scripts/rvm"
PATH=$PATH:$HOME/.rvm/bin # Add RVM to PATH for scripting

# tmux with 256 colors
alias tmux="TERM=screen-256color-bce tmux"

# mongodb
alias mongodb.start="mongod --fork --logpath /var/log/mongodb.log --logappend --config /usr/local/Cellar/mongodb/2.0.4-x86_64/mongod.conf"

# cd to the git root of the project you're in
cd.() {
  cd $(git rev-parse --show-toplevel)
}

# nginx
alias nginx-start="sudo nginx"
alias nginx-stop="sudo /usr/local/sbin/nginx -s stop"
alias nginx-reload="sudo /usr/local/sbin/nginx -s reload"
alias nginx-restart="nginx-stop; nginx-start;"
alias sites-enabled="cd /usr/local/etc/nginx/sites-enabled"

# php
alias php-stop="kill -USR2 `cat /usr/local/var/run/php-fpm.pid`"
alias l="ls -alh"

killport() {
  if [ -n "${1}" ]; then
    port=$1
  else
    # default (Rails-centric)
    port="3000"
  fi
  pid=`lsof -wni tcp:$port | awk 'NR==2 { print $2 }'`
  if [ -n "${pid}" ]; then
    kill -9 $pid
    echo "Killed process $pid"
  else
    echo "No processes were found listening on tcp:$port"
  fi
}
