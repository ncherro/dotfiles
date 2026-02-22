# stub pmodload - prezto modules are loaded explicitly via antidote
function pmodload { }

# --- Antidote ---
source ~/.antidote/antidote.zsh
antidote load $DOTFILES/zsh_plugins.txt

# --- SSH Agent ---
eval "$(keychain --eval --quiet ~/.ssh/id_ed25519)"

# --- PATH ---
export PATH="$HOME/.local/bin:$PATH"

# --- Misc ---
export LD_LIBRARY_PATH=/home/ebenezer/workspace/vid.stab:$LD_LIBRARY_PATH
