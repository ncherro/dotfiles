export HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
export SHELL=/opt/homebrew/bin/zsh

# --- Antidote ---
source $HOMEBREW_PREFIX/opt/antidote/share/antidote/antidote.zsh
antidote load $DOTFILES/zsh_plugins.txt

# --- Completions ---
FPATH=$HOMEBREW_PREFIX/share/zsh-completions:$FPATH
autoload -Uz compinit
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi
source "$HOMEBREW_PREFIX/opt/zsh-git-prompt/zshrc.sh"

# --- NVM (lazy loaded for faster startup) ---
export NVM_DIR="$HOME/.nvm"
_load_nvm() {
  unset -f nvm node npm npx yarn pnpm 2>/dev/null
  [ -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ] && \. "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
  [ -s "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm" ] && \. "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm"
}
nvm()  { _load_nvm && nvm "$@"; }
node() { _load_nvm && node "$@"; }
npm()  { _load_nvm && npm "$@"; }
npx()  { _load_nvm && npx "$@"; }
yarn() { _load_nvm && yarn "$@"; }
pnpm() { _load_nvm && pnpm "$@"; }

autoload -U add-zsh-hook
_auto_nvm_use() { [[ -f .nvmrc ]] && _load_nvm && nvm use; }
add-zsh-hook chpwd _auto_nvm_use
_auto_nvm_use

# --- Java & Maven ---
export JAVA_HOME="$(/usr/libexec/java_home -v 21)"
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

# --- Google Cloud SDK ---
source "$HOMEBREW_PREFIX/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc"
source "$HOMEBREW_PREFIX/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc"

# --- Postgres ---
export PGDATA=/usr/local/var/postgres
alias pg-start='pg_ctl -D /usr/local/var/postgres -l /usr/local/var/postgres/server.log start'
alias pg-stop='pg_ctl -D /usr/local/var/postgres stop -s -m fast'
alias pg-status='pg_ctl -D /usr/local/var/postgres status'

# --- Nginx ---
alias nginx-start="sudo nginx"
alias nginx-stop="sudo /usr/local/bin/nginx -s stop"
alias nginx-reload="sudo /usr/local/bin/nginx -s reload"
alias sites-enabled="cd /usr/local/etc/nginx/sites-enabled"
nginx-restart() { nginx-stop; nginx-start; }

# --- Kubernetes ---
alias k8s="kubectl"
alias k8s-contexts="grep '^- name: ' ~/.kube/config | awk '{print $3}'"
alias k8s-bash='k8s exec -it $(k8s get po | grep Running | awk "{print $1}" | tail -n 1) -- bash'

# --- GitHub ---
alias ghopen="git config --get remote.origin.url | sed 's/:/\//' | sed 's/git@/https:\/\//' | sed 's/\.git//' | xargs open"

ghpr() {
  gh pr view --web 2>/dev/null || echo "No PR found for branch: $(git rev-parse --abbrev-ref HEAD)"
}

# --- Misc ---
export NODE_PATH=/usr/local/lib/node_modules
export LSCOLORS=ExFxBxDxCxegedabagacad

alias mux="tmuxinator"
alias bazel=bazelisk
alias terminal="open -a Kitty"

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

# --- PATH ---
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/local/sbin:/usr/local/share/npm/bin:/opt/homebrew/opt/mysql-client/bin:/opt/homebrew/opt/mysql-client@8.4/bin:$HOME/.local/bin:$PATH"
export PATH="/Applications/IntelliJ IDEA.app/Contents/MacOS:$PATH"
export PATH="$HOME/scripts:$PATH"
export PATH="$PATH:$HOME/.rvm/bin"
