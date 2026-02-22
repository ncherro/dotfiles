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

