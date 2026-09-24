export DOTFILES=~/Projects/dotfiles

case "$(uname -s)" in
  Darwin) source $DOTFILES/zsh/mac.zsh ;;
  Linux)  source $DOTFILES/zsh/linux.zsh ;;
esac

source $DOTFILES/zsh/base.zsh
source $DOTFILES/zsh/tmux-workflows.zsh

export PATH="$HOME/.local/bin:$PATH"

# Machine-local overrides (gitignored)
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# A restart takes every tmux session with it, and the shell that comes back
# gives no sign that anything is missing.
#
# Tests for the server's socket rather than running `tmux ls`: a shell opening
# must never block on another process, and a wedged or slow tmux server would
# otherwise hang every new terminal. No fork, and no way to hang. The server
# exits when its last session closes, so the socket existing means there is
# something to attach to.
if [[ -o interactive && -z "$TMUX" && ! -S ${TMUX_TMPDIR:-/tmp}/tmux-${UID}/default ]]; then
  echo "no tmux sessions — 'resume' reopens what you were working on"
fi
