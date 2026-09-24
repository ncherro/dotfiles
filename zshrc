export DOTFILES=~/Projects/dotfiles

case "$(uname -s)" in
  Darwin) source $DOTFILES/zsh/mac.zsh ;;
  Linux)  source $DOTFILES/zsh/linux.zsh ;;
esac

source $DOTFILES/zsh/base.zsh
source $DOTFILES/zsh/tmux-workflows.zsh

# Spotify devex tooling (auto-managed by path_updater_lib.sh — do not remove)
# re-added automatically if removed -_-

# Machine-local overrides (gitignored)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

export PATH="$HOME/.local/bin:$PATH"
export PATH=/opt/spotify-devex/bin:$PATH

# A restart takes every tmux session with it, and the shell that comes back
# gives no sign that anything is missing. One tmux call, only in shells
# started outside tmux, and only while there is nothing to attach to.
if [[ -o interactive && -z "$TMUX" ]] && ! tmux ls &>/dev/null; then
  echo "no tmux sessions — 'resume' reopens what you were working on"
fi
