# stub pmodload - prezto modules are loaded explicitly via antidote
function pmodload { }

# --- Antidote ---
source ~/.antidote/antidote.zsh
antidote load $DOTFILES/zsh_plugins.txt

# --- SSH Agent ---
eval "$(keychain --eval --quiet ~/.ssh/id_ed25519)"

# --- PATH ---
export PATH="$HOME/.local/bin:$PATH"

# --- Browser opener (handles WSL vs native Linux) ---
_open() {
  if grep -qi microsoft /proc/version 2>/dev/null; then
    wslview "$@"
  else
    xdg-open "$@"
  fi
}

# --- GitHub ---
ghopen() {
  local url
  url=$(git config --get remote.origin.url | sed 's/:/\//' | sed 's/git@/https:\/\//' | sed 's/\.git//')
  _open "$url"
}

ghpr() {
  local url
  url=$(gh pr view --json url -q .url 2>/dev/null)
  if [[ -n "$url" ]]; then
    _open "$url"
  else
    echo "No PR found for branch: $(git rev-parse --abbrev-ref HEAD)"
  fi
}

# --- Misc ---
export LD_LIBRARY_PATH=/home/ebenezer/workspace/vid.stab:$LD_LIBRARY_PATH
