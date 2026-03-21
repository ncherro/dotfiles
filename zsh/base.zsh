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

# git worktree in ~/worktrees
gwt() {
  if [[ "$PWD" == *"/worktrees/"* ]]; then
    echo "Already in a worktree"
    return 1
  fi
  local root=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
  if [[ -z "$root" ]]; then
    echo "Not in a git repository"
    return 1
  fi
  local branch
  if [[ -n "$1" ]]; then
    branch="$1"
    local dest="$HOME/worktrees/${root}--${branch//\//-}"
    git worktree add -b "$branch" "$dest" master && cd "$dest" && tat
  else
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ "$branch" == "master" || "$branch" == "main" ]]; then
      echo "On $branch — pass a branch name to create a new worktree"
      return 1
    fi
    local dest="$HOME/worktrees/${root}--${branch//\//-}"
    if [[ -d "$dest" ]]; then
      cd "$dest" && tat
      return
    fi
    if [[ -n "$(git status --porcelain)" ]]; then
      echo "Working tree is not clean — commit or stash changes first"
      return 1
    fi
    git checkout master 2>/dev/null || git checkout main && \
      git worktree add "$dest" "$branch" && cd "$dest" && tat
  fi
}

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

alias gitpersonal="git config user.email \"ncherro@gmail.com\""

# --- GitHub ---
# Open the current repo in the browser
ghr() {
  local url
  url=$(git config --get remote.origin.url | sed 's/:/\//' | sed 's/git@/https:\/\//' | sed 's/\.git//')
  _open "$url"
}

# Open the current branch's PR in the browser
ghp() {
  gh pr view --web 2>/dev/null || echo "No PR found for branch: $(git rev-parse --abbrev-ref HEAD)"
}

# --- Tmux ---
# List tmux sessions, highlighting ones running processes
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

# Attach to a tmux session by fuzzy name match
tatt() {
  local match
  match=$(tmux ls -F '#{session_name}' 2>/dev/null | grep -F "$1" | head -1)
  if [ -n "$match" ]; then
    tmux at -t "$match"
  else
    echo "No session matching '$1'"
    return 1
  fi
}

# Attach or create a tmux session named after the repo/branch
tat() {
  # Optionally cd into a directory first
  if [[ -n "$1" ]]; then
    cd "$1" || return 1
  fi
  local session_name
  # In a git repo, use dirname--branch (or just dirname on main/master)
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    local branch=$(git rev-parse --abbrev-ref HEAD)
    local dirname=$(basename "$(dirname "$(git rev-parse --git-common-dir)")")
    if [[ "$branch" == "master" || "$branch" == "main" ]]; then
      session_name=$dirname
    else
      session_name="${dirname}--${branch}"
    fi
  else
    session_name=${PWD##*/}
  fi
  # tmux doesn't allow dots in session names
  session_name=${session_name//./-}
  if tmux ls 2>/dev/null | grep -q "^${session_name}:"; then
    tmux at -t "$session_name"
    return 0
  fi
  if command -v tmuxinator &>/dev/null && tmuxinator ls 2>/dev/null | grep -q "^${session_name}"; then
    tmuxinator start "$session_name"
    return 0
  fi
  tmux new -s "$session_name"
}

# Kill all tmux sessions
tks() { tmux kill-server; }

# --- FZF ---
(( $+commands[fzf] )) && source <(fzf --zsh 2>/dev/null)
export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*"'

# --- Misc ---
# cd to the git repo root
cd.() { cd "$(git rev-parse --show-toplevel)"; }

alias l="ls -alh"
alias stamp="date +%F-%H%M%S"
alias cap="nocorrect cap"
alias v="vim"
alias h="history"
alias dco=docker-compose
alias dc=docker-compose
 
alias c=claude

ulimit -n 10000
export CLICOLOR=1

setopt inc_append_history
setopt share_history

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

# --- Workspace / Worktrees ---
export WORKSPACE="$HOME/workspace"

# cd into ~/workspace
ws() { cd "$WORKSPACE/${1:-.}" }
# cd into ~/worktrees
wt() { cd "$HOME/worktrees/${1:-.}" }

_ws() { _path_files -W "$WORKSPACE" -/ }
_wt() { _path_files -W "$HOME/worktrees" -/ }
compdef _ws ws
compdef _wt wt
compdef _ws tat

# branch completion (requires compinit to have been called by platform file or plugins)
(( $+functions[compdef] )) && compdef _git_branch_complete gco gs


# The following lines have been added by Docker Desktop to enable Docker CLI completions.
fpath=(~/.docker/completions $fpath)
autoload -Uz compinit
compinit
# End of Docker CLI completions
