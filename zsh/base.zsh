export HISTFILE=~/.zhistory

export EDITOR='vim'
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export TZ=America/Chicago

# --- Git ---
export GIT_MERGE_AUTOEDIT=no

alias gp='git push'
alias gpf='git pf'
alias gpc='git push --set-upstream origin "$(git rev-parse --abbrev-ref HEAD 2> /dev/null)"'
alias gd='git add -N . && git diff && git reset'
alias gsq='git reset --soft $(git merge-base master HEAD)'
alias gdm='git branch --merged | grep -v "^\*\\|master" | xargs -n 1 git branch -d'
alias gs='git switch'
alias gfr='git pull --rebase'
alias gfa='git fetch --all'
alias glo='git log'
alias gsha="git rev-parse --short HEAD"
alias gti="git"
alias g-='gco -'

# git checkout with auto-prefix for new branches
unalias gco 2>/dev/null
gco() {
  if [[ "$1" == "-b" && -n "$2" && "$2" != $USER/* ]]; then
    git checkout -b "$USER/$2" "${@:3}"
  else
    git checkout "$@"
  fi
}

# branch completion (workaround for git 2.52+ bug)
_git_branch_complete() {
  compadd ${(f)"$(git branch -a 2>/dev/null | sed 's/^[* ]*//' | sed 's|remotes/origin/||' | sort -u)"}
}

deletemerged() {
  git branch --merged | grep -v "\*" | xargs -n 1 git branch -d
}

alias gitpersonal="git config user.email \"ncherro@gmail.com\""

# --- Tmux ---
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

tatt() { tmux at -t $1; }

tat() {
  dirname=${PWD##*/}
  if tmux ls 2>/dev/null | grep -q "^${dirname}:"; then
    tmux at -t "$dirname"
    return 0
  fi
  if command -v tmuxinator &>/dev/null && tmuxinator ls 2>/dev/null | grep -q "^${dirname}"; then
    tmuxinator start "$dirname"
    return 0
  fi
  tmux new -s "$dirname"
}

tks() { tmux kill-server; }

# --- FZF ---
(( $+commands[fzf] )) && source <(fzf --zsh 2>/dev/null)
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'

# --- Misc ---
cd.() { cd "$(git rev-parse --show-toplevel)"; }

alias l="ls -alh"
alias stamp="date +%F-%H%M%S"
alias cap="nocorrect cap"
alias v="vim"
alias h="history"
alias dco=docker-compose
alias dc=docker-compose
alias c=claude
alias ngrok="~/ngrok"

ulimit -n 10000
export CLICOLOR=1

setopt inc_append_history
setopt share_history

function exportFile() {
  set -o allexport; source $1; set +o allexport;
}

alias focus="sudo bash ~/block-sites.sh"
alias unfocus="sudo bash ~/unblock-sites.sh"
alias mux="tmuxinator"
alias bazel=bazelisk

# --- Maven ---
alias mcl='mvn clean'
alias mve='mvn verify'
alias mcv='mvn clean verify'
alias mcut='mvn clean verify -DskipITs'
alias mcit='mvn clean verify -Dsurefire.skip=true'
alias mci='mvn clean install'
alias mcg='mvn clean generate-sources'
alias mcp='mvn clean package -P uberJar'
alias mvn-clear-cache="rm -Rf ~/.m2/repository"
alias openapi-generator-cli='java -jar ~/openapi-generator-cli.jar'

# --- SDKMAN ---
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# --- Kubernetes ---
alias k8s="kubectl"
alias k8s-contexts="grep '^- name: ' ~/.kube/config | awk '{print $3}'"
alias k8s-bash='k8s exec -it $(k8s get po | grep Running | awk "{print $1}" | tail -n 1) -- bash'

# --- pyenv ---
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

# --- Prompt ---
autoload -Uz promptinit; promptinit
prompt pure

# --- Workspace ---
export WORKSPACE="$HOME/workspace"
alias ws="cd $WORKSPACE"

# branch completion (requires compinit to have been called by platform file or plugins)
(( $+functions[compdef] )) && compdef _git_branch_complete gco gs
